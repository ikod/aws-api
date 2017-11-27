import std.stdio;
import std.process;
import std.experimental.logger;

import apis.s3;
import apis.ec2;
import utils;

void main(string[] args){
    string aws_access = environment.get("AWS_ACCESS", null);
    string aws_secret = environment.get("AWS_SECRET", null);
    if ( aws_secret is null || aws_access is null ) {
        writeln("Both AWS_ACCESS and AWS_SECRET must present in environment");
        return;
    }
    globalLogLevel(LogLevel.info);

    immutable ec2c = ec2_config(aws_access, aws_secret, "us-east-1");
    auto zones = DescribeAvailabilityZones(ec2c, DescribeAvailabilityZonesRequest_Type());
    auto instances = DescribeInstances(ec2c, DescribeInstancesRequest_Type());

    immutable s3c = s3_config(aws_access, aws_secret, "us-east-1");

    auto b = ListBuckets(s3c);
    foreach(bucket; b.Buckets) {
        writefln("bucket = %s", bucket.Name);
        auto rq = ListObjectsRequest_Type();
        rq.Bucket = bucket.Name;
        auto olist = ListObjects(s3c, rq);
        if ( olist.Contents.length == 0 ) {
            continue;
        }
        foreach(o; olist.Contents) {
            writefln("%s %d - %s", o.LastModified, o.Size, o.Key);
        }
//        break;
    }

    globalLogLevel(LogLevel.info);
    {
        auto q = ListBucketMetricsConfigurationsRequest_Type();
        q.Bucket="7b4f";
        writeln(ListBucketMetricsConfigurations(s3c, q));
    }
    try {
        auto gbp = GetBucketPolicyRequest_Type();
        gbp.Bucket = "7b4f";
        writeln(GetBucketPolicy(s3c, gbp));
    } catch (APIException e) {
        writeln(e);
    }
    // GetObject return stream
    auto gorq = GetObjectRequest_Type();
    gorq.Bucket = "7b4f";
    gorq.Key = "k.sh";
    auto r = GetObject(s3c, gorq);
    while (!r.empty) {
        write(cast(string)r.front);
        r.popFront;
    }
}