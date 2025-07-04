"""
Reddit Processing Lambda Function
Processes raw Reddit data stored in S3 and performs sentiment analysis
"""

import json
import os
import boto3
import logging
from datetime import datetime, timezone
from botocore.exceptions import ClientError
import re

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# Environment variables
S3_BUCKET_NAME = os.environ['S3_BUCKET_NAME']
DYNAMODB_TABLE_NAME = os.environ['DYNAMODB_TABLE_NAME']
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

def lambda_handler(event, context):
    """
    Main Lambda handler function triggered by S3 events
    """
    try:
        logger.info(f"Processing S3 event for environment: {ENVIRONMENT}")
        
        # Process each S3 record
        processed_count = 0
        
        for record in event['Records']:
            if record['eventSource'] == 'aws:s3':
                bucket = record['s3']['bucket']['name']
                key = record['s3']['object']['key']
                
                logger.info(f"Processing S3 object: {key}")
                
                # Only process files in the raw-data directory
                if key.startswith('raw-data/'):
                    try:
                        process_reddit_post(bucket, key)
                        processed_count += 1
                    except Exception as e:
                        logger.error(f"Error processing {key}: {str(e)}")
                        continue
                else:
                    logger.info(f"Skipping non-raw-data file: {key}")
        
        logger.info(f"Successfully processed {processed_count} files")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Processing completed successfully',
                'processed_count': processed_count,
                'environment': ENVIRONMENT
            })
        }
        
    except Exception as e:
        logger.error(f"Error in processing function: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Processing failed',
                'message': str(e)
            })
        }

def process_reddit_post(bucket, key):
    """
    Process a single Reddit post from S3
    """
    # Get post data from S3
    post_data = get_post_from_s3(bucket, key)
    
    # Perform sentiment analysis
    sentiment_data = analyze_sentiment(post_data)
    
    # Extract additional insights
    insights = extract_insights(post_data)
    
    # Combine all data
    processed_data = {
        **post_data,
        **sentiment_data,
        **insights,
        'processed_at': datetime.now(timezone.utc).isoformat(),
        'processing_version': '1.0'
    }
    
    # Store processed data in S3
    store_processed_data(processed_data)
    
    # Update DynamoDB with processing results
    update_dynamodb_record(processed_data)
    
    logger.info(f"Successfully processed post {post_data['post_id']}")

def get_post_from_s3(bucket, key):
    """
    Retrieve post data from S3
    """
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        post_data = json.loads(response['Body'].read())
        return post_data
        
    except ClientError as e:
        logger.error(f"Error retrieving {key} from S3: {str(e)}")
        raise

def analyze_sentiment(post_data):
    """
    Perform sentiment analysis on post title and content
    This is a simplified example - you would integrate with a real sentiment analysis service
    """
    # Combine title and text for analysis
    text_to_analyze = f"{post_data['title']} {post_data['selftext']}"
    
    # Simple keyword-based sentiment analysis (replace with actual ML service)
    sentiment_score = simple_sentiment_analysis(text_to_analyze)
    
    # Determine sentiment category
    if sentiment_score > 0.1:
        sentiment_category = 'positive'
    elif sentiment_score < -0.1:
        sentiment_category = 'negative'
    else:
        sentiment_category = 'neutral'
    
    return {
        'sentiment_score': sentiment_score,
        'sentiment_category': sentiment_category,
        'confidence': abs(sentiment_score)
    }

def simple_sentiment_analysis(text):
    """
    Simple sentiment analysis using keyword matching
    Replace this with actual sentiment analysis service (AWS Comprehend, etc.)
    """
    positive_words = ['good', 'great', 'awesome', 'excellent', 'amazing', 'love', 'fantastic', 'wonderful']
    negative_words = ['bad', 'terrible', 'awful', 'hate', 'horrible', 'disgusting', 'worst', 'stupid']
    
    text_lower = text.lower()
    
    positive_count = sum(1 for word in positive_words if word in text_lower)
    negative_count = sum(1 for word in negative_words if word in text_lower)
    
    # Simple scoring mechanism
    total_words = len(text.split())
    if total_words == 0:
        return 0.0
    
    sentiment_score = (positive_count - negative_count) / max(total_words, 1)
    return min(max(sentiment_score, -1.0), 1.0)  # Clamp between -1 and 1

def extract_insights(post_data):
    """
    Extract additional insights from post data
    """
    insights = {
        'word_count': len(post_data['title'].split()) + len(post_data['selftext'].split()),
        'has_url': bool(post_data.get('url') and post_data['url'] != post_data.get('permalink', '')),
        'engagement_ratio': calculate_engagement_ratio(post_data),
        'topic_keywords': extract_keywords(post_data['title'] + ' ' + post_data['selftext']),
        'post_length_category': categorize_post_length(post_data['selftext'])
    }
    
    return insights

def calculate_engagement_ratio(post_data):
    """
    Calculate engagement ratio (comments per upvote)
    """
    score = post_data.get('score', 0)
    num_comments = post_data.get('num_comments', 0)
    
    if score <= 0:
        return 0.0
    
    return num_comments / score

def extract_keywords(text):
    """
    Extract basic keywords from text
    """
    # Simple keyword extraction - remove common words and get most frequent
    common_words = {'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should', 'this', 'that', 'these', 'those'}
    
    words = re.findall(r'\b\w+\b', text.lower())
    filtered_words = [word for word in words if word not in common_words and len(word) > 3]
    
    # Count word frequency
    word_freq = {}
    for word in filtered_words:
        word_freq[word] = word_freq.get(word, 0) + 1
    
    # Return top 5 keywords
    sorted_words = sorted(word_freq.items(), key=lambda x: x[1], reverse=True)
    return [word for word, count in sorted_words[:5]]

def categorize_post_length(text):
    """
    Categorize post length
    """
    word_count = len(text.split())
    
    if word_count == 0:
        return 'title_only'
    elif word_count < 50:
        return 'short'
    elif word_count < 200:
        return 'medium'
    else:
        return 'long'

def store_processed_data(processed_data):
    """
    Store processed data in S3
    """
    key = f"processed-data/{processed_data['subreddit']}/{processed_data['post_id']}.json"
    
    try:
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=key,
            Body=json.dumps(processed_data, indent=2),
            ContentType='application/json'
        )
        logger.debug(f"Stored processed post {processed_data['post_id']} in S3")
        
    except ClientError as e:
        logger.error(f"Error storing processed post {processed_data['post_id']} in S3: {str(e)}")
        raise

def update_dynamodb_record(processed_data):
    """
    Update DynamoDB record with processing results
    """
    table = dynamodb.Table(DYNAMODB_TABLE_NAME)
    
    try:
        table.update_item(
            Key={
                'post_id': processed_data['post_id'],
                'timestamp': int(processed_data['timestamp'])
            },
            UpdateExpression='SET processed = :processed, sentiment_score = :score, sentiment_category = :category, word_count = :word_count, processed_at = :processed_at',
            ExpressionAttributeValues={
                ':processed': True,
                ':score': processed_data['sentiment_score'],
                ':category': processed_data['sentiment_category'],
                ':word_count': processed_data['word_count'],
                ':processed_at': processed_data['processed_at']
            }
        )
        logger.debug(f"Updated DynamoDB record for post {processed_data['post_id']}")
        
    except ClientError as e:
        logger.error(f"Error updating DynamoDB record for post {processed_data['post_id']}: {str(e)}")
        raise