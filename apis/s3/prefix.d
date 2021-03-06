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
import std.regex;
import std.stdio;
import std.typecons;

import utils;
import drivers;

struct s3_config {
    package string aws_access;
    package string aws_secret;
    package string region;
    package string endpoint = "s3.amazonaws.com";
    package string service = "s3";

    this(string a, string s, string r = "us-east-1", string e = "s3.amazonaws.com") {
        aws_access = a;
        aws_secret = s;
        region = r;
        endpoint = e;
    }
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
            //
            // urlencode member, place it into uri
            // if uri contain template like {Key+} - do not encode /
            //
            string key = `\{%s\}`.format((*locationName).str);
            string key_greedy = `\{%s\+\}`.format((*locationName).str);
            auto re        = regex(key);
            auto re_greedy = regex(key_greedy);
            auto m = matchFirst(requestUri, re);
            if ( !m.empty ) {
                requestUri = requestUri.replace(m[0], urlEncoded(i.serialize(memberName)));
            }
            m = matchFirst(requestUri, re_greedy);
            if ( !m.empty ) {
                requestUri = requestUri.replace(m[0], urlEncoded(i.serialize(memberName), "/"));
            }
        }
        if ( location && (*location).str == "header" && locationName ) {
            string k,v;
            k = (*locationName).str;
            v = i.serialize(memberName);
            if ( v ) {
                result.headers[k] = "%s".format(v);
            }
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

auto handleRedirect(Result r, s3_config config, string op_descriptor) {
    s3_config new_config;
    auto x_amz_bucket_region = "x-amz-bucket-region" in r.responseHeaders();
    if ( x_amz_bucket_region ) {
        string region = *x_amz_bucket_region;
        return tuple!("ok", "config")(true, s3_config(config.aws_access, config.aws_secret, region, "s3-%s.amazonaws.com".format(region)));
    }
    return tuple!("ok", "config")(false, s3_config());
}

/// end of prefix

