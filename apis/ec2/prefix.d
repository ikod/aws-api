module apis.ec2;

import std.datetime;
import std.array;
import std.algorithm;

import utils;
import drivers;

struct ec2_config {
    package immutable string aws_access;
    package immutable string aws_secret;
    package immutable string region;
    package immutable string endpoint;
    package immutable string service = "ec2";

    this(string a, string s, string r) {
        aws_access = a;
        aws_secret = s;
        region = r;
        endpoint = "ec2." ~ region ~ ".amazonaws.com";
    }
}

// http://docs.aws.amazon.com/AWSEC2/latest/APIReference/CommonParameters.html#common-parameters-sigv4

void customize_query(string name, ref string[string] query) {
    query["Version"] = api_version;
    query["Action"] = name;
}

