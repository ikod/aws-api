module drivers;

import std.typecons;
import std.traits;

import utils;

import requests;

alias Result = Tuple!(int, "responseCode", ubyte[], "responseBody");

auto exec(Auth_Args args, string[string] headers) {
    ubyte[] r_body;
    int     r_code;
    Request rq = Request();
    //rq.verbosity = 1;
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
    default:
        assert(0);
    }
    r_code = r.code;
    r_body = r.responseBody.data;
    return Result(r_code, r_body);
}
