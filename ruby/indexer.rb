require 'elasticity'

S3_COPY_JAR = "s3://elasticmapreduce/libs/s3distcp/role/s3distcp.jar"

S3_BUCKET = 'dogo-nutch'
NUTCH_VERSION = 1.8
NUTCH_JAR_PATH = "s3://#{S3_BUCKET}/lib/apache-nutch-#{NUTCH_VERSION}.job.jar"
LOG_URI = "s3://#{S3_BUCKET}/logs"

# Crawl Settings
DEPTH = 3
# CLUSTERSIZE - 1
NUM_FETCHERS = 6
# TopN is NUM_FETCHERS * 50000
TOPN = 250000
NUM_FETCHER_THREADS = 50
TIME_LIMIT_FETCH = 60

COMMON_OPTIONS = "-D mapred.reduce.tasks.speculative.execution=false -D mapred.map.tasks.speculative.execution=false"

SEGMENT = "20140603205343"
SOLR_URL = "http://ec2-54-237-133-101.compute-1.amazonaws.com:8983/solr"

# Create a job flow with your AWS credentials
# jobflow = Elasticity::JobFlow.new('AWS access key', 'AWS secret key')

# Omit credentials to use the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables
jobflow = Elasticity::JobFlow.new('AKIAJ53J2XCFKBZQDI3A', 'SAbYBeEZvIQ3XFv4iKAIWL2gVSj6QcMyV9cqAb+9')
jobflow.name = 'Nutch Crawler'
jobflow.log_uri = LOG_URI
jobflow.enable_debugging = true

# NOTE: Amazon requires that all new accounts specify a VPC subnet when launching jobs.
# If you're on an existing account, this is unnecessary however new AWS accounts require
# subnet IDs be specified when launching jobs.
# jobflow.ec2_subnet_id = 'YOUR_SUBNET_ID_HERE'

# Copy CrawlDB
step = Elasticity::CustomJarStep.new(S3_COPY_JAR)
step.name = 'Copy CrawlDB'
step.arguments = %W(--dest hdfs:///user/hadoop/crawl/crawldb --src s3://#{S3_BUCKET}/crawl/crawldb --srcPattern .*)
jobflow.add_step(step)

# Copy Segments
step = Elasticity::CustomJarStep.new(S3_COPY_JAR)
step.name = 'Copy Segments'
step.arguments = %W(--dest hdfs:///user/hadoop/crawl/segments --src s3://#{S3_BUCKET}/crawl/segments --srcPattern .*)
jobflow.add_step(step)

# Copy LinkDB
step = Elasticity::CustomJarStep.new(S3_COPY_JAR)
step.name = 'Copy LinkDB'
step.arguments = %W(--dest hdfs:///user/hadoop/crawl/linkdb --src s3://#{S3_BUCKET}/crawl/linkdb --srcPattern .*)
jobflow.add_step(step)

# Index
step = Elasticity::CustomJarStep.new(NUTCH_JAR_PATH)
step.name = 'Index'
step.arguments = %W(org.apache.nutch.indexer.IndexingJob -D solr.server.url=#{SOLR_URL} crawl/crawldb -linkdb crawl/linkdb crawl/segments/#{SEGMENT})
jobflow.add_step(step)

# Clean Index
step = Elasticity::CustomJarStep.new(NUTCH_JAR_PATH)
step.name = 'Clean Index'
step.arguments = %W(org.apache.nutch.indexer.CleaningJob -D solr.server.url=#{SOLR_URL} crawl/crawldb)
jobflow.add_step(step)

# Let's go!
jobflow.run
