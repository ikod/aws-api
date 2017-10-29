module apis.s3;

import std.datetime;
import std.array;
import std.algorithm;
import std.conv;
import std.string;
import core.stdc.time: strftime;

import utils;
import drivers;

struct s3_config {
    package immutable string aws_access;
    package immutable string aws_secret;
    package immutable string region;
    package immutable string endpoint = "s3.amazonaws.com";
    package immutable string service = "s3";

    this(string a, string s, string r = "us-east-1") {
        aws_access = a;
        aws_secret = s;
        region = r;
    }
}

void customize_query(string name, ref string[string] query) {
}