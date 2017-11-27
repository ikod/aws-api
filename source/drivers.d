module drivers;

import std.typecons;
import std.traits;

import utils;

import requests;

//alias Result = Tuple!(int, "code", ubyte[], "responseBody", string[string], "responseHeaders");

alias Result = requests.Response;

auto exec(T)(Auth_Args args, string[string] headers, bool streaming, T payload) {
    ubyte[] r_body;
    int     r_code;
    Request rq = Request();
    rq.verbosity = 1;
    rq.useStreaming = streaming;
    rq.addHeaders(headers);

    string url = "https://" ~ args.endpoint ~ args.requestUri;
    if ( args.queryString.length ) {
        url ~= "?" ~ args.queryString;
    }
    Response r;
    switch (args.method) {
    case "GET":
        r = rq.exec!"GET"(url);
        break;
    case "HEAD":
        r = rq.exec!"HEAD"(url);
        break;
    case "POST":
        r = rq.exec!"POST"(url);
        break;
    case "DELETE":
        r = rq.exec!"DELETE"(url);
        break;
    case "PUT":
        r = rq.exec!"PUT"(url, payload);
        break;
    default:
        assert(0);
    }
    //r_code = r.code;
    //r_body = r.responseBody.data;
    //import std.stdio;
    //writeln(cast(string)r_body);
    //return Result(r_code, r_body);
    return r;
}

auto exec(Auth_Args args, string[string] headers, bool streaming) {
    ubyte[] r_body;
    int     r_code;
    Request rq = Request();
    rq.verbosity = 1;
    rq.useStreaming = streaming;
    rq.addHeaders(headers);

    string url = "https://" ~ args.endpoint ~ args.requestUri;
    if ( args.queryString.length ) {
        url ~= "?" ~ args.queryString;
    }
    Response r;
    switch (args.method) {
    case "GET":
        r = rq.exec!"GET"(url);
        break;
    case "HEAD":
        r = rq.exec!"HEAD"(url);
        break;
    case "POST":
        r = rq.exec!"POST"(url);
        break;
    case "PUT":
        r = rq.exec!"PUT"(url);
        break;
    case "DELETE":
        r = rq.exec!"DELETE"(url);
        break;
    default:
        assert(0);
    }
    //r_code = r.code;
    //r_body = r.responseBody.data;
    //import std.stdio;
    //writeln(cast(string)r_body);
    //return Result(r_code, r_body);
    return r;
}

string[string] responseHeaders(Result r) {
    return r.responseHeaders();
}