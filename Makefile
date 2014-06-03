# Makefile for Running Nutch on AWS EMR
#
#
# run
# % make
# to get the list of options.
#
# based on Karan Bathia's Makefile from: https://github.com/lila/SimpleEMR/blob/master/Makefile

#
# commands setup (ADJUST THESE IF NEEDED)
#
ACCESS_KEY_ID =
SECRET_ACCESS_KEY =
EC2_KEY_NAME =
S3_BUCKET =
CRAWLER_NAME =

# Elasticsearch Settings
ES_HOST =
ES_PORT =
ES_CLUSTERNAME =
ES_INDEX =

AWS_REGION = us-east-1
KEYPATH	= ${EC2_KEY_NAME}.pem
CLUSTERSIZE= 3
MASTER_INSTANCE_TYPE = m1.large
SLAVE_INSTANCE_TYPE = m1.large

# Crawl Settings
DEPTH = 3
# CLUSTERSIZE - 1
NUM_FETCHERS = 5
# TopN is NUM_FETCHERS * 50000
TOPN = 250000
NUM_FETCHER_THREADS = 50
TIME_LIMIT_FETCH=60

#
AWS	= aws
ANT = ant
S3_API = s3api
#
NUTCH_VERSION = 1.8

ifeq ($(origin AWS_CONFIG_FILE), undefined)
	export AWS_CONFIG_FILE:=aws.conf
endif



#
# variables used internally in makefile
#
seedfiles := $(wildcard urls/*)

AWS_CONF = '[default]\naws_access_key_id=${ACCESS_KEY_ID}\naws_secret_access_key=${SECRET_ACCESS_KEY}\nregion=${AWS_REGION}'

NUTCH-SITE-CONF= "<?xml version=\"1.0\"?> \
<?xml-stylesheet type=\"text/xsl\" href=\"configuration.xsl\"?> \
<configuration> \
<property> \
  <name>http.agent.name</name> \
  <value>${CRAWLER_NAME}</value> \
  <description></description> \
</property> \
<property> \
  <name>http.robots.agents</name> \
  <value>${CRAWLER_NAME},*</value> \
  <description></description> \
</property> \
<property> \
  <name>plugin.includes</name> \
  <value>protocol-http|urlfilter-regex|parse-(html|tika)|index-(basic|anchor)|indexer-solr|indexer-elastic|scoring-opic|urlnormalizer-(pass|regex|basic)</value> \
  <description>Regular expression naming plugin directory names to \
  include.  Any plugin not matching this expression is excluded. \
  In any case you need at least include the nutch-extensionpoints plugin. By \
  default Nutch includes crawling just HTML and plain text via HTTP, \
  and basic indexing and search plugins. In order to use HTTPS please enable \
  protocol-httpclient, but be aware of possible intermittent problems with the \
  underlying commons-httpclient library. \
  </description> \
</property> \
<!-- Elasticsearch properties --> \
\
<property> \
  <name>elastic.host</name> \
  <value>${ES_HOST}</value> \
  <description>The hostname to send documents to using TransportClient. Either host \
  and port must be defined or cluster.</description> \
</property> \
\
<property> \
  <name>elastic.port</name> \
  <value>${ES_PORT}</value> \
  <description> \
  </description> \
</property> \
\
<property> \
  <name>elastic.cluster</name> \
  <value>${ES_CLUSTERNAME}</value> \
  <description>The cluster name to discover. Either host and port must be defined \
  or cluster.</description> \
</property> \
\
<property> \
  <name>elastic.index</name> \
  <value>${ES_INDEX}</value> \
  <description>Default index to send documents to.</description> \
</property> \
\
<property> \
  <name>elastic.max.bulk.docs</name> \
  <value>250</value> \
  <description>Maximum size of the bulk in number of documents.</description> \
</property> \
\
<property> \
  <name>elastic.max.bulk.size</name> \
  <value>2500500</value> \
  <description>Maximum size of the bulk in bytes.</description> \
</property> \
</configuration>"

INSTANCES = '{  \
	"InstanceCount": ${CLUSTERSIZE},  \
	"MasterInstanceType": "${MASTER_INSTANCE_TYPE}",  \
	"HadoopVersion": "1.0.3",  \
	"KeepJobFlowAliveWhenNoSteps": false,  \
	"SlaveInstanceType": "${SLAVE_INSTANCE_TYPE}",  \
	"Ec2KeyName": "${EC2_KEY_NAME}"  \
}'

STEPS = '[ \
	{  \
	  "HadoopJarStep": { \
	      "MainClass": "org.apache.nutch.crawl.Injector", \
	      "Args": \
	        ["crawl/crawldb", "s3://${S3_BUCKET}/urls"], \
	      "Jar": "s3://${S3_BUCKET}/lib/apache-nutch-${NUTCH_VERSION}.job.jar" \
	    }, \
	  "Name": "Inject Seed URLs" \
	}, \
	{  \
		"HadoopJarStep": { \
				"MainClass": "org.apache.nutch.crawl.Generator", \
				"Args": \
					["crawl/crawldb", "crawl/segments", "-topN", "${TOPN}", "-numFetchers", "${NUM_FETCHERS}", "-noFilter"], \
				"Jar": "s3://${S3_BUCKET}/lib/apache-nutch-${NUTCH_VERSION}.job.jar" \
			}, \
		"Name": "Generate Fetch List" \
	}, \
	{  \
		"HadoopJarStep": { \
				"MainClass": "org.apache.nutch.fetcher.Fetcher", \
				"Args": \
					["crawl/segments/*", "-D", "fetcher.timelimit.mins=${TIME_LIMIT_FETCH}", "-noParsing", "-threads", "${NUM_FETCHER_THREADS}"], \
				"Jar": "s3://${S3_BUCKET}/lib/apache-nutch-${NUTCH_VERSION}.job.jar" \
			}, \
		"Name": "Fetch Segment" \
	}, \
	{  \
		"HadoopJarStep": { \
				"MainClass": "org.apache.nutch.parse.ParseSegment", \
				"Args": \
					["crawl/segments/*", "-D", "mapred.skip.attempts.to.start.skipping=2", "-D", "mapred.skip.map.max.skip.records=1"], \
				"Jar": "s3://${S3_BUCKET}/lib/apache-nutch-${NUTCH_VERSION}.job.jar" \
			}, \
		"Name": "Parse Segment" \
	}, \
	{  \
		"HadoopJarStep": { \
				"MainClass": "org.apache.nutch.crawl.CrawlDb", \
				"Args": \
					["crawl/crawldb", "crawl/segments/*"], \
				"Jar": "s3://${S3_BUCKET}/lib/apache-nutch-${NUTCH_VERSION}.job.jar" \
			}, \
		"Name": "Update Crawl DB" \
	}, \
	{  \
	  "HadoopJarStep": { \
	      "MainClass": "org.apache.nutch.segment.SegmentMerger", \
	      "Args": \
	        ["crawl/mergedsegments", "-dir", "crawl/segments"], \
	      "Jar": "s3://${S3_BUCKET}/lib/apache-nutch-${NUTCH_VERSION}.job.jar" \
	    }, \
	  "Name": "Merge Segments" \
	}, \
	{  \
	  "HadoopJarStep": { \
	      "Args": \
	        ["--src","hdfs:///user/hadoop/crawl/crawldb","--dest","s3://${S3_BUCKET}/crawl/crawldb","--srcPattern",".*"], \
	      "Jar": "s3://elasticmapreduce/libs/s3distcp/role/s3distcp.jar" \
	    }, \
	  "Name": "Copy CrawlDB to S3" \
	}, \
	{  \
	  "HadoopJarStep": { \
	      "Args": \
	        ["--src","hdfs:///user/hadoop/crawl/linkdb","--dest","s3://${S3_BUCKET}/crawl/linkdb","--srcPattern",".*"], \
	      "Jar": "s3://elasticmapreduce/libs/s3distcp/role/s3distcp.jar" \
	    }, \
	  "Name": "Copy LinkDB to S3" \
	}, \
	{  \
	  "HadoopJarStep": { \
	      "Args": \
	        ["--src","hdfs:///user/hadoop/crawl/segments","--dest","s3://${S3_BUCKET}/crawl/segments","--srcPattern",".*"], \
	      "Jar": "s3://elasticmapreduce/libs/s3distcp/role/s3distcp.jar" \
	    }, \
	  "Name": "Copy Segments to S3" \
	}, \
	{  \
		"HadoopJarStep": { \
				"Args": \
					["--src","hdfs:///user/hadoop/crawl/mergedsegments","--dest","s3://${S3_BUCKET}/crawl/mergedsegments","--srcPattern",".*"], \
				"Jar": "s3://elasticmapreduce/libs/s3distcp/role/s3distcp.jar" \
			}, \
		"Name": "Copy Merged Segments to S3" \
	} \
]'

#
# make targets
#
.PHONY: help
help:
	@echo "help for Makefile for running Nutch on AWS EMR "
	@echo "make create - create an EMR Cluster with default settings "
	@echo "make destroy - clean up everything (terminate cluster )"
	@echo
	@echo "make ssh - log into master node of cluster"


#
# top level target to tear down cluster and cleanup everything
#
.PHONY: destroy
destroy:
	-${AWS} emr terminate-job-flows --job-flow-ids `cat ./jobflowid`
	rm ./jobflowid

#
# top level target to create a new cluster of c1.mediums
#
.PHONY: create
create:
	@ if [ -a ./jobflowid ]; then echo "jobflowid exists! exiting"; exit 1; fi
	@ echo creating EMR cluster
	${AWS} --output text  emr  run-job-flow --name NutchCrawler --instances ${INSTANCES} --steps ${STEPS} --log-uri "s3://${S3_BUCKET}/logs" | head -1 > ./jobflowid

#
# load the nutch jar and seed files to s3
#

.PHONY: bootstrap
bootstrap: | aws.conf apache-nutch-${NUTCH_VERSION}-src.zip apache-nutch-${NUTCH_VERSION}/build/apache-nutch-${NUTCH_VERSION}.job  creates3bucket seedfiles2s3
	${AWS} ${S3_API} put-object --bucket ${S3_BUCKET} --key lib/apache-nutch-${NUTCH_VERSION}.job.jar --body apache-nutch-${NUTCH_VERSION}/build/apache-nutch-${NUTCH_VERSION}.job

#
#  create se bucket
#
.PHONY: creates3bucket
creates3bucket:
	${AWS} ${S3_API} create-bucket --bucket ${S3_BUCKET}

#
#  copy from url foder to s3
#
.PHONY: seedfiles2s3 $(seedfiles)
seedfiles2s3: $(seedfiles)

$(seedfiles):
	${AWS} ${S3_API} put-object --bucket ${S3_BUCKET} --key $@ --body $@

#
#  download and unzip nutch source code
#
apache-nutch-1.6-src.zip:
	curl -O http://archive.apache.org/dist/nutch/1.6/apache-nutch-1.6-src.zip
	unzip apache-nutch-1.6-src.zip
	echo ${NUTCH-SITE-CONF} > apache-nutch-1.6/conf/nutch-site.xml

apache-nutch-1.8-src.zip:
	curl -O http://archive.apache.org/dist/nutch/1.8/apache-nutch-1.8-src.zip
	unzip apache-nutch-1.8-src.zip
	echo ${NUTCH-SITE-CONF} > apache-nutch-1.8/conf/nutch-site.xml

#
#  build nutch job jar
#
apache-nutch-${NUTCH_VERSION}/build/apache-nutch-${NUTCH_VERSION}.job: $(wildcard apache-nutch-${NUTCH_VERSION}/conf/*)
	${ANT} -f apache-nutch-${NUTCH_VERSION}/build.xml

#
# ssh: quick wrapper to ssh into the master node of the cluster
#
ssh: aws.conf
	h=`${AWS} emr describe-job-flows --job-flow-ids \`cat ./jobflowid\` | grep "MasterPublicDnsName" | cut -d "\"" -f 4`; echo "h=$$h"; if [ -z "$$h" ]; then echo "master not provisioned"; exit 1; fi
	h=`${AWS} emr describe-job-flows --job-flow-ids \`cat ./jobflowid\` | grep "MasterPublicDnsName" | cut -d "\"" -f 4`; ssh -L 9100:localhost:9100 -i ${KEYPATH} "hadoop@$$h"

#
# created the config file for aws-cli
#
aws.conf:
	@echo -e ${AWS_CONF} > aws.conf

s3.list: aws.conf
	${AWS} --output text ${S3_API} list-buckets
