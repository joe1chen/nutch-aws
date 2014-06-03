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
SECRET_ACCESS_KEY
EC2_KEY_NAME =
AWS_REGION = us-east-1
KEYPATH	= ${EC2_KEY_NAME}.pem
S3_BUCKET =
CLUSTERSIZE	= 3
DEPTH = 3
TOPN = 5
MASTER_INSTANCE_TYPE = m1.small
SLAVE_INSTANCE_TYPE = m1.small
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
  <value>efcrawler</value> \
  <description></description> \
</property> \
<property> \
  <name>http.robots.agents</name> \
  <value>mycrawler,*</value> \
  <description></description> \
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
	      "MainClass": "org.apache.nutch.crawl.Crawl", \
	      "Args": \
	        ["s3://${S3_BUCKET}/urls", "-dir", "crawl", "-depth", "${DEPTH}", "-topN", "${TOPN}"], \
	      "Jar": "s3://${S3_BUCKET}/lib/apache-nutch-${NUTCH_VERSION}.job.jar" \
	    }, \
	  "Name": "nutch-crawl" \
	}, \
	{  \
	  "HadoopJarStep": { \
	      "MainClass": "org.apache.nutch.segment.SegmentMerger", \
	      "Args": \
	        ["crawl/mergedsegments", "-dir", "crawl/segments"], \
	      "Jar": "s3://${S3_BUCKET}/lib/apache-nutch-${NUTCH_VERSION}.job.jar" \
	    }, \
	  "Name": "nutch-crawl" \
	}, \
	{  \
	  "HadoopJarStep": { \
	      "Args": \
	        ["--src","hdfs:///user/hadoop/crawl/crawldb","--dest","s3://${S3_BUCKET}/crawl/crawldb","--srcPattern",".*","--outputCodec","snappy"], \
	      "Jar": "s3://elasticmapreduce/libs/s3distcp/role/s3distcp.jar" \
	    }, \
	  "Name": "crawlData2S3" \
	 }, \
	{  \
	  "HadoopJarStep": { \
	      "Args": \
	        ["--src","hdfs:///user/hadoop/crawl/linkdb","--dest","s3://${S3_BUCKET}/crawl/linkdb","--srcPattern",".*","--outputCodec","snappy"], \
	      "Jar": "s3://elasticmapreduce/libs/s3distcp/role/s3distcp.jar" \
	    }, \
	  "Name": "crawlData2S3" \
	 }, \
	{  \
	  "HadoopJarStep": { \
	      "Args": \
	        ["--src","hdfs:///user/hadoop/crawl/mergedsegments","--dest","s3://${S3_BUCKET}/crawl/segments","--srcPattern",".*","--outputCodec","snappy"], \
	      "Jar": "s3://elasticmapreduce/libs/s3distcp/role/s3distcp.jar" \
	    }, \
	  "Name": "crawlData2S3" \
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
