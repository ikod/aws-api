import std.stdio;
import std.process;
import std.experimental.logger;

import apis.s3;
import apis.ec2;

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
            writefln("%s - %s", o.LastModified, o.Key);
        }
        break;
    }
}