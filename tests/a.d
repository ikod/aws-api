import std.stdio;
import std.process;

import apis.s3;

void main(string[] args){
    string aws_access = environment.get("AWS_ACCESS", null);
    string aws_secret = environment.get("AWS_SECRET", null);
    if ( aws_secret is null || aws_access is null ) {
        writeln("Both AWS_ACCESS and AWS_SECRET must present in environment");
        return;
    }
    immutable s3c = s3_config(aws_access, aws_secret, "us-east-1");
    auto buckets = ListBuckets(s3c);
    writeln(buckets);
}