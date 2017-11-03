module utils;

import std.datetime;
import std.string;
import std.traits;
import std.xml;

import requests;

auto decodeFromXml(T)(Element e) {
    T V;
    static if (is(T==struct )) {
        V = T(e);
    } else static if ( isArray!T && !isSomeString!T ) {
        V = decodeArray!T(e);
    } else {
        V = decodeElement!T(e);
    }
    return V;
}

auto decodeFromXmlFlattenedArray(T)(Element e) {
    import std.range.primitives;
    import std.stdio;

    alias ArrayElement_Type = ElementType!T;
    ArrayElement_Type result;
    result = decodeFromXml!ArrayElement_Type(e);
    return result;
}

T decodeArray(T)(Element e) {
    T result;
    alias _Member_Type = ForeachType!T;
    _Member_Type _m;

    foreach(i; e.elements) {

        static if (is(_Member_Type == struct )) {
            _m = _Member_Type(i);
        } else
        static if ( isSomeString!_Member_Type ) {
            _m = decodeElement!_Member_Type(i);
        } else
        static if ( isArray!_Member_Type ) {
            _m = decodeArray!_Member_Type(i);
        } else {
            _m = decodeElement!_Member_Type(i);
        }
        result ~= _m;
    }
    return result;
}

T decodeElement(T)(Element e) {
    import std.stdio;
    import std.conv;
    return to!T(e.text);
}


string toRFC822date(SysTime st) {
    import core.stdc.time: gmtime, strftime;
    auto t = st.toUnixTime();
    char[64] buffer;
    string format = "%a, %d %b %Y %H:%M:%S +0000";
    auto ret = strftime(buffer.ptr, 256, toStringz(format), gmtime(&t));
    auto res = buffer[0 .. ret].idup;
    return res;
}

string urlEncoded(string p) pure @safe {
    immutable string[dchar] translationTable = [
        ' ':  "%20", '!': "%21", '*': "%2A", '\'': "%27", '(': "%28", ')': "%29",
        ';':  "%3B", ':': "%3A", '@': "%40", '&':  "%26", '=': "%3D", '+': "%2B",
        '$':  "%24", ',': "%2C", '/': "%2F", '?':  "%3F", '#': "%23", '[': "%5B",
        ']':  "%5D", '%': "%25",
    ];
    return p.translate(translationTable);
}

struct Auth_Args {
    string access;
    string secret;
    string endpoint;
    string region;
    string service;
    string requestUri;
    string method;
    string queryString;
    immutable ubyte[] payload;
}

string[string] build_headers(const Auth_Args args) {
    string aws_access_key_id = args.access;
    string aws_secret_access_key = args.secret;
    string region = args.region;
    string service = args.service;
    string endpoint = args.endpoint;
    string requestUri = args.requestUri;
    string queryString = args.queryString;
    string method = args.method;
    auto payload = args.payload;

    import std.digest.sha;
    import std.digest.hmac;
    import std.string;

    ubyte[] sign(scope const(ubyte)[] key, scope const(ubyte)[] msg) {
        auto hmac = HMAC!SHA256(key);
        auto digest = hmac.put(msg)
                  .finish();
        return digest.dup;
    }

    ubyte[] getSignatureKey(string key, string date, string regionName, string serviceName) {
        auto kDate = sign(("AWS4" ~ key).representation, date.representation);
        auto kRegion = sign(kDate, regionName.representation);
        auto kService = sign(kRegion, serviceName.representation);
        auto kSigning = sign(kService, "aws4_request".representation);
        return kSigning;
    }

    string[string] headers;
    auto now = SysTime(Clock.currStdTime, UTC());
    auto uri = URI("https://" ~ endpoint ~ requestUri);
    string algorithm = "AWS4-HMAC-SHA256";
    string amzdate = (now - now.fracSecs).toISOString();
    string date = amzdate[0..8];
    string canonical_uri = uri.path;
    string canonical_querystring = queryString;
    string canonical_headers, signed_headers;
    canonical_headers = "host:" ~ uri.host ~ "\n" ~ "x-amz-date:" ~ amzdate ~ "\n";
    signed_headers = "host;x-amz-date";

    string payload_hash = sha256Of(payload).toHexString.toLower();
    string canonical_request = method ~ "\n" ~ canonical_uri ~ "\n" ~
                canonical_querystring ~ "\n" ~
                canonical_headers ~ "\n" ~
                signed_headers ~ "\n" ~
                payload_hash;

    string credential_scope = date ~ "/" ~ region ~ "/" ~ service ~ "/aws4_request";

    auto string_to_sign = algorithm ~ "\n" ~
                            amzdate ~ "\n" ~
                            credential_scope ~ "\n" ~
                            sha256Of(canonical_request).toHexString!(LetterCase.lower);
    auto signing_key = getSignatureKey(aws_secret_access_key, date, region, service);

    string signature = HMAC!SHA256(signing_key).
                        put(string_to_sign.representation).
                        finish().
                        toHexString!(LetterCase.lower);
    string authorization_header = algorithm ~ " " ~
                "Credential=" ~ aws_access_key_id ~ "/" ~ credential_scope ~ ", " ~
                "SignedHeaders=" ~ signed_headers ~ ", " ~ "Signature=" ~ signature;


    headers["x-amz-date"] = amzdate;
    headers["host"] = endpoint;
    headers["Authorization"] = authorization_header;
    headers["x-amz-content-sha256"] = payload_hash;
    return headers;
}
