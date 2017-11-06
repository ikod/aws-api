module apis.s3;

import std.datetime;
import std.array;
import std.algorithm;
import std.conv;
import std.string;
import std.json;
import std.xml;
import core.stdc.time: strftime;
import std.experimental.logger;
import std.variant;

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

private auto serializeRequest(T)(T i, JSONValue[string] op) {
    SerializedRequest result;
    JSONValue[string] input;

    input = fastParseJSON(i.descriptor).object;

    auto http = op["http"].object;
    string method = http["method"].str;
    string requestUri = http["requestUri"].str;
    string[] query;

    auto input_members = input["members"].object;
    foreach(memberName,d; input_members) {
        auto descriptor = d.object;
        auto locationName = "locationName" in descriptor;
        auto location = "location" in descriptor;
        auto shape = "shape" in descriptor;
        if ( location && (*location).str == "uri" && locationName ) {
            // place it into uri
            string to_replace = "{%s}".format((*locationName).str);
            requestUri = requestUri.replace(to_replace, i.serialize(memberName));
        }
        if ( location && (*location).str == "querystring" && locationName ) {
            // place it into query
            string k,v;
            k = (*locationName).str;
            v = i.serialize(memberName);
            if ( v ) {
                query ~= "%s=%s".format(k, v);
            }
        }
    }
    result.method = method;
    result.requestUri = requestUri;
    result.query = query;
    return result;
}

private auto serializeRequest(JSONValue[string] op) {
    SerializedRequest result;

    auto http = op["http"].object;
    string method = http["method"].str;
    string requestUri = http["requestUri"].str;
    string[] query;

    result.method = method;
    result.requestUri = requestUri;
    result.query = query;
    return result;
}

/// end of prefix

