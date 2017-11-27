module utils;

import std.datetime;
import std.string;
import std.traits;
import std.xml;
import std.json;
import std.typecons;
import std.functional;
import std.experimental.logger;
import std.algorithm;

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

string urlEncoded(string p, string safe = "") pure @safe {
    string[dchar] translationTable = [
        ' ':  "%20", '!': "%21", '*': "%2A", '\'': "%27", '(': "%28", ')': "%29",
        ';':  "%3B", ':': "%3A", '@': "%40", '&':  "%26", '=': "%3D", '+': "%2B",
        '$':  "%24", ',': "%2C", '/': "%2F", '?':  "%3F", '#': "%23", '[': "%5B",
        ']':  "%5D", '%': "%25",
    ];
    string result;
    foreach(s; safe) {
        translationTable.remove(s);
    }
    return p.translate(translationTable);
}
unittest {
    assert(urlEncoded("IDontNeedNoPercentEncoding") == "IDontNeedNoPercentEncoding");
    assert(urlEncoded("~~--..__") == "~~--..__");
    assert(urlEncoded("0123456789") == "0123456789");

    assert(urlEncoded("abc//~", "/") == "abc//~");
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
    immutable (ubyte)[] payload;
}

string[string] signV4(const Auth_Args args) {
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
    string queryString2canonicalQuery(string queryString) {
        if (queryString.length == 0) return "";
        if (queryString[0] == '?') {
            queryString = queryString[1..$];
        }
        string res = queryString.
                split("&").
                map!(s => s.canFind("=") ? s : s~"=").
                join("&");
        return res;
    }

    tracef("args: %s", args);

    string[string] headers;
    auto now = SysTime(Clock.currStdTime, UTC());
    auto uri = URI("https://" ~ endpoint ~ requestUri);
    string algorithm = "AWS4-HMAC-SHA256";
    string amzdate = (now - now.fracSecs).toISOString();
    string date = amzdate[0..8];
    string canonical_uri = uri.path;
    string canonical_querystring = queryString2canonicalQuery(uri.query ~ args.queryString); // XXX we have to join and sort here
    string canonical_headers, signed_headers;

    canonical_headers = "host:" ~ uri.host ~ "\n" ~ "x-amz-date:" ~ amzdate ~ "\n";
    signed_headers = "host;x-amz-date";

    string payload_hash;
    if ( payload == "UNSIGNED-PAYLOAD" ) {
        payload_hash = "UNSIGNED-PAYLOAD";
    } else {
        payload_hash = sha256Of(payload).toHexString.toLower();
    }
    string canonical_request = method ~ "\n" ~ canonical_uri ~ "\n" ~
                canonical_querystring ~ "\n" ~
                canonical_headers ~ "\n" ~
                signed_headers ~ "\n" ~
                payload_hash;

    tracef("Canonical request: <%s>", canonical_request);

    string credential_scope = date ~ "/" ~ region ~ "/" ~ service ~ "/aws4_request";

    auto string_to_sign = algorithm ~ "\n" ~
                            amzdate ~ "\n" ~
                            credential_scope ~ "\n" ~
                            sha256Of(canonical_request).toHexString!(LetterCase.lower);

    tracef("string to sign: <%s>", string_to_sign);

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

string getXMLErrorCode(string msg) {
    auto d = new Document(msg);
    if ( d.tag.name != "Error" ) {
        return null;
    }
    auto e = d.elements.filter!(e => e.tag.name == "Code");
    if ( !e.empty ) {
        return e.front.text;
    }
    return null;
}

class APIException: Exception {
    short httpCode;
    string apiCode;

    this(short httpCode, string apiCode, string file = __FILE__, size_t line = __LINE__) {
        this.httpCode = httpCode;
        this.apiCode = apiCode;
        super(apiCode, file, line);
    }
}

alias SerializedRequest = Tuple!(string, "method", string, "requestUri", string[string], "headers", string[], "query", immutable(ubyte)[], "payload");

auto slowParseJSON(string data) pure {
    return parseJSON(data);
}
alias fastParseJSON = memoize!slowParseJSON;

auto RESTXMLReply(T)(Document d) {
    //import std.stdio;
    //writefln("items: %s", d.items);
    return T(d);
}

auto RESTXMLReplyBlob(const(ubyte)[] blob) {
    return blob;
}

auto RESTXMLReplyString(const(ubyte)[] blob) {
    return cast(string)blob;
}
