"""
Reddit Ingestion Lambda Function
Fetches posts from specified subreddits and stores them in S3 and DynamoDB
"""

import json
import os
import boto3
import praw
from datetime import datetime, timezone
import logging
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# Environment variables
REDDIT_CLIENT_ID = os.environ['REDDIT_CLIENT_ID']
REDDIT_CLIENT_SECRET = os.environ['REDDIT_CLIENT_SECRET']
REDDIT_USER_AGENT = os.environ['REDDIT_USER_AGENT']
S3_BUCKET_NAME = os.environ['S3_BUCKET_NAME']
DYNAMODB_TABLE_NAME = os.environ['DYNAMODB_TABLE_NAME']
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

# Default subreddits to monitor
DEFAULT_SUBREDDITS = ['technology', 'news', 'worldnews', 'politics']

def lambda_handler(event, context):
    """
    Main Lambda handler function
    """
    try:
        logger.info(f"Starting Reddit ingestion for environment: {ENVIRONMENT}")
        
        # Initialize Reddit API client
        reddit = praw.Reddit(
            client_id=REDDIT_CLIENT_ID,
            client_secret=REDDIT_CLIENT_SECRET,
            user_agent=REDDIT_USER_AGENT
        )
        
        # Get subreddits from event or use defaults
        subreddits = event.get('subreddits', DEFAULT_SUBREDDITS)
        posts_per_subreddit = event.get('posts_per_subreddit', 25)
        
        total_posts_processed = 0
        
        for subreddit_name in subreddits:
            try:
                logger.info(f"Processing subreddit: {subreddit_name}")
                posts_processed = process_subreddit(reddit, subreddit_name, posts_per_subreddit)
                total_posts_processed += posts_processed
                logger.info(f"Processed {posts_processed} posts from r/{subreddit_name}")
                
            except Exception as e:
                logger.error(f"Error processing subreddit {subreddit_name}: {str(e)}")
                continue
        
        logger.info(f"Total posts processed: {total_posts_processed}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Reddit ingestion completed successfully',
                'total_posts_processed': total_posts_processed,
                'subreddits_processed': subreddits,
                'environment': ENVIRONMENT
            })
        }
        
    except Exception as e:
        logger.error(f"Error in Reddit ingestion: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Reddit ingestion failed',
                'message': str(e)
            })
        }

def process_subreddit(reddit, subreddit_name, posts_per_subreddit):
    """
    Process posts from a specific subreddit
    """
    subreddit = reddit.subreddit(subreddit_name)
    posts_processed = 0
    
    # Get DynamoDB table
    table = dynamodb.Table(DYNAMODB_TABLE_NAME)
    
    try:
        # Fetch hot posts from subreddit
        for post in subreddit.hot(limit=posts_per_subreddit):
            try:
                # Extract post data
                post_data = extract_post_data(post, subreddit_name)
                
                # Store in S3 (raw data)
                store_in_s3(post_data)
                
                # Store metadata in DynamoDB
                store_in_dynamodb(table, post_data)
                
                posts_processed += 1
                
            except Exception as e:
                logger.error(f"Error processing post {post.id}: {str(e)}")
                continue
                
    except Exception as e:
        logger.error(f"Error fetching posts from r/{subreddit_name}: {str(e)}")
        raise
    
    return posts_processed

def extract_post_data(post, subreddit_name):
    """
    Extract relevant data from a Reddit post
    """
    timestamp = datetime.now(timezone.utc).timestamp()
    
    post_data = {
        'post_id': post.id,
        'subreddit': subreddit_name,
        'title': post.title,
        'selftext': post.selftext,
        'author': str(post.author) if post.author else '[deleted]',
        'score': post.score,
        'upvote_ratio': post.upvote_ratio,
        'num_comments': post.num_comments,
        'created_utc': post.created_utc,
        'url': post.url,
        'permalink': post.permalink,
        'is_self': post.is_self,
        'over_18': post.over_18,
        'spoiler': post.spoiler,
        'locked': post.locked,
        'stickied': post.stickied,
        'timestamp': timestamp,
        'ingestion_date': datetime.now(timezone.utc).isoformat(),
        'environment': ENVIRONMENT
    }
    
    return post_data

def store_in_s3(post_data):
    """
    Store post data in S3 as JSON
    """
    key = f"raw-data/{post_data['subreddit']}/{post_data['post_id']}.json"
    
    try:
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=key,
            Body=json.dumps(post_data, indent=2),
            ContentType='application/json'
        )
        logger.debug(f"Stored post {post_data['post_id']} in S3")
        
    except ClientError as e:
        logger.error(f"Error storing post {post_data['post_id']} in S3: {str(e)}")
        raise

def store_in_dynamodb(table, post_data):
    """
    Store post metadata in DynamoDB
    """
    item = {
        'post_id': post_data['post_id'],
        'timestamp': int(post_data['timestamp']),
        'subreddit': post_data['subreddit'],
        'title': post_data['title'],
        'author': post_data['author'],
        'score': post_data['score'],
        'num_comments': post_data['num_comments'],
        'created_utc': post_data['created_utc'],
        'ingestion_date': post_data['ingestion_date'],
        'environment': post_data['environment'],
        'processed': False  # Flag for processing pipeline
    }
    
    try:
        table.put_item(Item=item)
        logger.debug(f"Stored post {post_data['post_id']} in DynamoDB")
        
    except ClientError as e:
        logger.error(f"Error storing post {post_data['post_id']} in DynamoDB: {str(e)}")
        raise