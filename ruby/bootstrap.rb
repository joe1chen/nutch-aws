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

# Inject Seed URLs
step = Elasticity::CustomJarStep.new(NUTCH_JAR_PATH)
step.name = 'Inject Seed URLs'
step.arguments = %W(org.apache.nutch.crawl.Injector crawl/crawldb s3://#{S3_BUCKET}/urls)
jobflow.add_step(step)

# Generate Fetch List
step = Elasticity::CustomJarStep.new(NUTCH_JAR_PATH)
step.name = 'Generate Fetch List'
step.arguments = %W(org.apache.nutch.crawl.Generator crawl/crawldb crawl/segments -topN #{TOPN} -numFetchers #{NUM_FETCHERS} -noFilter #{COMMON_OPTIONS})
jobflow.add_step(step)

# Copy CrawlDB
step = Elasticity::CustomJarStep.new(S3_COPY_JAR)
step.name = 'Copy CrawlDB'
step.arguments = %W(--src hdfs:///user/hadoop/crawl/crawldb --dest s3://#{S3_BUCKET}/crawl/crawldb --srcPattern .*)
jobflow.add_step(step)

# Copy Segments
step.name = 'Copy Segments'
step = Elasticity::CustomJarStep.new(S3_COPY_JAR)
step.arguments = %W(--src hdfs:///user/hadoop/crawl/segments --dest s3://#{S3_BUCKET}/crawl/segments --srcPattern .*)
jobflow.add_step(step)

# Let's go!
jobflow.run
