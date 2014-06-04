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

# Fetch Segment
step = Elasticity::CustomJarStep.new(NUTCH_JAR_PATH)
step.name = 'Fetch Segment'
step.arguments = %W(org.apache.nutch.fetcher.Fetcher crawl/segments/#{SEGMENT} -D fetcher.timelimit.mins=#{TIME_LIMIT_FETCH} -noParsing -threads #{NUM_FETCHER_THREADS} #{COMMON_OPTIONS})
jobflow.add_step(step)

# Parse Segment
step = Elasticity::CustomJarStep.new(NUTCH_JAR_PATH)
step.name = 'Parse Segment'
step.arguments = %W(org.apache.nutch.parse.ParseSegment crawl/segments/#{SEGMENT} -D mapred.skip.attempts.to.start.skipping=2 -D mapred.skip.map.max.skip.records=1 #{COMMON_OPTIONS})
jobflow.add_step(step)

# Update CrawlDB
step = Elasticity::CustomJarStep.new(NUTCH_JAR_PATH)
step.name = 'Update CrawlDB'
step.arguments = %W(org.apache.nutch.crawl.CrawlDb crawl/crawldb crawl/segments/#{SEGMENT} #{COMMON_OPTIONS})
jobflow.add_step(step)

# Invert Links
step = Elasticity::CustomJarStep.new(NUTCH_JAR_PATH)
step.name = 'Invert Links'
step.arguments = %W(org.apache.nutch.crawl.LinkDb crawl/linkdb crawl/segments/*)
jobflow.add_step(step)

# Copy CrawlDB
step = Elasticity::CustomJarStep.new(S3_COPY_JAR)
step.name = 'Copy CrawlDB'
step.arguments = %W(--src hdfs:///user/hadoop/crawl/crawldb --dest s3://#{S3_BUCKET}/crawl/crawldb --srcPattern .*)
jobflow.add_step(step)

# Copy Segments
step = Elasticity::CustomJarStep.new(S3_COPY_JAR)
step.name = 'Copy Segments'
step.arguments = %W(--src hdfs:///user/hadoop/crawl/segments --dest s3://#{S3_BUCKET}/crawl/segments --srcPattern .*)
jobflow.add_step(step)

# Copy LinkDB
step = Elasticity::CustomJarStep.new(S3_COPY_JAR)
step.name = 'Copy LinkDB'
step.arguments = %W(--src hdfs:///user/hadoop/crawl/linkdb --dest s3://#{S3_BUCKET}/crawl/linkdb --srcPattern .*)
jobflow.add_step(step)


# Let's go!
jobflow.run
