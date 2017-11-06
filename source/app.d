import std.stdio;
import std.json;
import std.array;
import std.algorithm;
import std.datetime;
import std.string;
import std.file;
import std.path;

import std.experimental.logger;

import requests;

void processShape(string name, JSONValue shape, File output, JSONValue shapes) {
    void processString(JSONValue data) {
        if ( false && "enum" in data.object ) {
            output.writefln("enum %s_Type: string {_init_=\"\", %s};\n", name,
                data.object["enum"].array.
                    map!(o =>
                        "%s=\"%s\"".format(o.str.
                            replace(" ", "_").
                            replace("-", "_").
                            replace(":", "_").
                            replace("*", "_").
                            replace(".", "_").
                            replace("/", "_").
                            replace("(", "_").
                            replace(")", "_").
                            capitalize(), o.str)).
                    join(", ")
            );
        } else {
            output.writefln("alias %s_Type = string;\n", name);
        }
    }
    void processMap(JSONValue data) {
        auto o = data.object;
        auto key = o["key"].object["shape"].str;
        auto value = o["value"].object["shape"].str;
        output.writefln("// map %s", name);
        output.writefln("alias %s_Type = %s_Type[%s_Type];\n", name, value, key);
    }
    void processType(T)(JSONValue data) {
        output.writefln("alias %s_Type = %s;\n", name, T.stringof);
    }
    void processList(JSONValue data) {
        auto member = data.object["member"].object["shape"].str;
        output.writefln("alias %s_Type = %s_Type[];\n", name, member);
    }
    void processSysTime(JSONValue data) {
        output.writeln();
        output.writefln("struct %s_Type {", name);
        output.writeln("    SysTime value;");
        output.writeln("    string toString() {return value.toRFC822date;};");
        output.writeln("    this(Element xml){");
        output.writeln("        value = SysTime.fromISOExtString(xml.text);");
        output.writeln("    }");
        output.writeln("};");
    }

    void processStructure(JSONValue data) {
        JSONValue[string] members = data.object["members"].object;
        string[string]    member_types;
        foreach(k,v; members) {
            member_types[k] = v.object["shape"].str ~ "_Type";
        }
        output.writefln("struct %s_Type {", name);

        auto required = "required" in data.object;

        if ( member_types.length ) {
            output.writefln("    alias Values = Algebraic!(%s);", member_types.values.join(", "));
            output.writeln( "    Values[string] dict;");
            output.writeln( "    string serialize(string memberName) {");
            output.writeln( "        switch(memberName) {");
            foreach(k,v; members) {
            output.writefln("        case \"%s\":", k);
            output.writefln("            if ( memberName in dict ) {");
            output.writefln("                return to!string(*dict[memberName].peek!%s);", member_types[k]);
            output.writeln( "            } else {");
            output.writeln( "                return null;");
            output.writeln( "            }");
            }
            output.writeln( "        default: errorf(\"No such member %s\", memberName); assert(0);");
            output.writeln( "        }");
            output.writeln( "    }");

            foreach(k,v; members) {
            output.writefln("    void opDispatch(string s)(%s v) if (s ==\"%s\") {", member_types[k], k);
            output.writefln("        dict[\"%s\"] = v;", k);
            output.writefln("    }");
            output.writefln("    auto opDispatch(string s)() if (s == \"%s\") {", k);
            output.writefln("        if (\"%s\" !in dict ) return %s.init;", k, member_types[k]);
            output.writefln("        return dict[\"%s\"].get!(%s);", k, member_types[k]);
            output.writefln("    }");
            }
        }
        output.writefln("    string descriptor = `%s`;", data.toJSON(true));

        output.writefln("    this(Element xml) {");
        output.writefln("        foreach(e; xml.elements) {\n" ~
                        "            switch(e.tag.name) {");

        foreach(member_name, member_data; data.object["members"].object) {
            string tag;
            string member_type = member_data.object["shape"].str;
            auto   member_info = shapes.object[member_type].object;
            auto locationName = "locationName" in member_data;
            if ( locationName ) {
                tag = (*locationName).str;
            } else {
                tag = member_name;
            }
            if ( "deprecated" in member_data ) {
                continue;
            }
            if ( member_info["type"].str == "list" && "flattened" in member_info ) {
                output.writefln(
                        `             case "%s":` ~ "\n" ~
                        `                 if ("%s" in dict ) {` ~ "\n" ~
                        `                     dict["%s"] ~= decodeFromXmlFlattenedArray!%s_Type(e);` ~ "\n" ~
                        `                 } else {` ~ "\n" ~
                        `                     dict["%s"] = [decodeFromXmlFlattenedArray!%s_Type(e)];` ~ "\n" ~
                        `                 }` ~ "\n" ~
                        `                 break;`
                        , tag, member_name, member_name, member_type, member_name, member_type);
            } else {
                output.writefln(
                        q{             case "%s": dict["%s"] = decodeFromXml!%s_Type(e);break;}, tag, member_name, member_type);
            }
        }

        output.writefln("            default: error(\"Unknown tag \", e.tag.name);");
        output.writefln("            }");
        output.writefln("        }");
        output.writefln("    }");
        output.writeln("};");

        output.writeln();
    }

    void processStructure1(JSONValue data) {
        string[string]  Types;
        string[]        required = "required" in data.object ?
                                data.object["required"].array.map!(o => o.str).array
                                : [];

        //output.writefln("//\n// structure %s %s\n//", name, data);
        output.writefln("struct %s_Type {", name);

        foreach(m; data.object["members"].object.byKeyValue) {
            auto member_data = m.value;
            string member_type = member_data.object["shape"].str;
            output.writefln("    %s_Type %s;", member_type, m.key);
            Types[m.key] = member_type;
        }
        if ( required ) {
            output.writefln("    this(%s) {", required.
                map!(a => "%s_Type %s".format(Types[a], a)).
                join(", "));
            foreach(r; required) {
                output.writefln("        this.%s = %s;", r, r);
            }
            output.writeln("    }");
        }
        output.writefln("    this(Element xml) {");
        output.writefln("        foreach(e; xml.elements) {\n" ~
                        "            switch(e.tag.name) {");
        foreach(m; data.object["members"].object.byKeyValue) {
            auto member_data = m.value;
            auto member_name = m.key;
            string tag;
            string member_type = member_data.object["shape"].str;
            auto   member_info = shapes.object[member_type].object;
            auto locationName = "locationName" in member_data;
            if ( locationName ) {
                tag = (*locationName).str;
            } else {
                tag = member_name;
            }
            if ( "deprecated" in member_data ) {
                continue;
            }
            if ( member_info["type"].str == "list" && "flattened" in member_info ) {
                output.writefln(
                        `             case "%s":` ~
                        `                 if ("%s" in dict )\n` ~
                        `                     %s ~= decodeFromXmlFlattenedArray!%s_Type(e);\n` ~
                        `                 else {\n` ~
                        `                     %s = [decodeFromXmlFlattenedArray!%s_Type(e)];\n` ~
                        `                 }\n` ~
                        `                 break;\n`
                        , tag, member_name, member_type);
            } else {
                output.writefln(
                        q{             case "%s": %s = decodeFromXml!%s_Type(e);break;}, tag, member_name, member_type);
            }
        }

        output.writefln("            default: error(\"Unknown tag \", e.tag.name);");
        output.writefln("            }");
        output.writefln("        }");
        output.writefln("    }");
        output.writeln("};");
    }
    string shapeType = shape.object["type"].str;
    switch(shapeType) {
        case "structure":
            processStructure(shape);
            break;
        case "list":
            processList(shape);
            break;
        case "string":
            processString(shape);
            break;
        case "timestamp":
            processSysTime(shape);
            break;
        case "integer":
            processType!int(shape);
            break;
        case "long":
            processType!long(shape);
            break;
        case "blob":
            processType!(ubyte[])(shape);
            break;
        case "boolean":
            processType!bool(shape);
            break;
        case "float":
            processType!float(shape);
            break;
        case "double":
            processType!double(shape);
            break;
        case "map":
            processMap(shape);
            break;
        default:
            writeln("unknown type ", shapeType);
    }
}

//string handle_operation_input(string input, in JSONValue shapes) {
//    auto input_descriptor = shapes.object[input];
//    string result;
//
//    foreach(m; input_descriptor.object["members"].object.byKeyValue){
//        try {
//            string member = m.key;
//            if ( "location" !in m.value.object ) {
//                continue;
//            }
//            string location = m.value.object["location"].str;
//            string locationName = m.value.object["locationName"].str;
//            string member_shape = m.value.object["shape"].str;
//            //
//            // find each 'locationName' in each 'location' and replace it with input.member
//            // if it doesn't equeal to .init
//            //
//            switch(location){
//            case "uri":
//                result ~= q{    uri = uri.replace("{%s}", to!string(input.%s));%s}
//                    .format(locationName, member, "\n");
//                break;
//            case "header":
//                result ~= q{    if ( input.%s != %s_Type.init) headers["%s"] = to!string(input.%s);%s}
//                    .format(member, member_shape, locationName, member, "\n");
//                break;
//            case "querystring":
//                result ~= q{    if ( input.%s != %s_Type.init) query["%s"] = to!string(input.%s);%s}
//                    .format(member, member_shape, locationName, member, "\n");
//                break;
//            default:
//                break;
//            }
//        } catch (Error e) {
//            errorf("catched exception on %s", m.key);
//        }
//    }
//    return result;
//}

void processOperation(string api_name, string name, JSONValue data, JSONValue shapes, File o) {
    string outputType = "output" in data.object ?
                            data.object["output"].object["shape"].str
                            : null;
    string inputType = "input" in data.object ?
                            data.object["input"].object["shape"].str
                            : null;
    if ( inputType ) {
        o.writefln("%s %s(%s_config config, %s_Type input) {", outputType ? outputType ~ "_Type" : "void", name, api_name, inputType);
    } else {
        o.writefln("%s %s(%s_config config) {", outputType ? outputType ~ "_Type" : "void", name, api_name);
    }

    o.writefln("    string descriptor = `%s`;", data.toJSON(true).splitLines.map!(s => "    " ~ s).join("\n"));

    if ( inputType ) {
        o.writefln(`    auto sr = serializeRequest!%s_Type(input, fastParseJSON(descriptor).object);`, inputType);
    } else {
        o.writefln(`    auto sr = serializeRequest(fastParseJSON(descriptor).object);`);
    }

    o.writeln("    string         method = sr.method;");
    o.writeln("    string         requestUri = sr.requestUri;");
    o.writeln("    string[string] headers = sr.headers;");
    o.writeln("    string[]       query = sr.query;");

    o.writeln(q{
    string queryString = query.sort.join("&");

    Auth_Args args = {access: config.aws_access,
                    secret: config.aws_secret,
                    region: config.region,
                    endpoint: config.endpoint,
                    service: config.service,
                    requestUri: requestUri,
                    method: method,
                    queryString: queryString};

    auto h = build_headers(args);
    foreach(k,v; h) {
        headers[k] = v;
    }
    auto r = drivers.exec(args, headers);
    });
    if ( outputType !is null ) {
        o.writefln(
        "    auto xml = new Document(cast(string)r.responseBody);\n" ~
        "    auto result = %s_Type(xml);\n", outputType);
        o.writefln("    return result;");
    }

    o.writefln("}\n");
}

//void processOperation1(string api_name, string name, JSONValue data, JSONValue shapes, File o) {
//    string http_method = data.object["http"].object["method"].str;
//    string http_requestUri = data.object["http"].object["requestUri"].str;
//    string outputType = "output" in data.object ?
//                            data.object["output"].object["shape"].str
//                            : null;
//    string documentationUrl = "documentationUrl" in data.object ?
//                            data.object["documentationUrl"].str
//                            : null;
//    string documentation = "documentation" in data.object ?
//                            data.object["documentation"].str
//                            : null;
//    string inputType = "input" in data.object ?
//                            data.object["input"].object["shape"].str
//                            : null;
//
//    o.writefln("///\n/// %s", name);
//    if ( documentationUrl ) {
//        o.writefln("/// %s", documentationUrl);
//    }
//    if ( documentation ) {
//        o.writefln("/// %s", documentation);
//    }
//    o.writeln("///");
//    if ( inputType ) {
//        o.writefln("%s %s(%s_config config, %s_Type input) {", outputType ? outputType ~ "_Type" : "void", name, api_name, inputType);
//    } else {
//        o.writefln("%s %s(%s_config config) {", outputType ? outputType ~ "_Type" : "void", name, api_name);
//    }
//    o.writefln("    immutable string method = \"%s\";", http_method);
//    o.writefln("    string uri = \"%s\";\n", http_requestUri);
//    o.writeln( "    string[string] query;");
//    o.writeln( "    string[string] headers;");
//
//    if (inputType ) {
//        o.writeln(handle_operation_input(inputType, shapes));
//    }
//
//    o.writefln(q{    customize_query("%s", query);}.format(name));
//
//    o.writeln(q{
//    string queryString = query.byKeyValue
//        .map!(p => "%s=%s".format(p.key.urlEncoded, p.value.urlEncoded))
//        .join("&");
//
//    Auth_Args args = {access: config.aws_access,
//                    secret: config.aws_secret,
//                    region: config.region,
//                    endpoint: config.endpoint,
//                    service: config.service,
//                    requestUri: uri,
//                    method: method,
//                    queryString: queryString};
//
//    foreach(p; build_headers(args).byKeyValue) {
//        headers[p.key] = p.value;
//    }
//    auto r = drivers.exec(args, headers);
//    });
//
//    //o.writeln(q{
//    //Request rq = Request();
//    //rq.addHeaders(headers);
//    //rq.verbosity = 1;
//    //
//    //string url = "https://" ~ config.endpoint ~ uri;
//    //if ( queryString.length ) {
//    //    url ~= "?" ~ queryString;
//    //}
//    //
//    //auto rs = rq.exec!"%s"(url);}
//    //.format(http_method));
//    //
//    if ( outputType !is null ) {
//        o.writefln(
//        "    auto xml = new Document(cast(string)r.body);\n" ~
//        "    auto result = %s_Type(xml);\n", outputType);
//        o.writefln("    return result;");
//    }
//    o.writefln("}\n");
//}

void generate(DirEntry api_file) {
    infof("Generate d file for %s", api_file.name);
    string api_json = cast(string)read(api_file.name);
    auto top = parseJSON(api_json);
    auto metadata = top.object["metadata"];
    auto shapes = top.object["shapes"];
    auto operations = top.object["operations"];


    string api_name = dirName(api_file.name).split(dirSeparator)[$-1];

    string output_path = dirName(api_file.name).split(dirSeparator)[0..$-1].join(dirSeparator);
    string output_file_name = "%s%s%s.d".format(output_path, dirSeparator, api_name);

    string prefix_file_name = dirName(api_file.name) ~ "%sprefix.d".format(dirSeparator);
    string prefix = cast(string)read(prefix_file_name);
    File output = File(output_file_name, "w");

    output.rawWrite(prefix);

    output.writefln(q{immutable string api_version = "%s";}.format(metadata.object["apiVersion"].str));

    foreach(kv; shapes.object.byKeyValue) {
        processShape(kv.key, kv.value, output, shapes);
    }
    foreach(kv; operations.object.byKeyValue) {
        processOperation(api_name, kv.key, kv.value, shapes, output);
    }
    output.close();
}

void main()
{
    foreach (string api; dirEntries("apis", SpanMode.shallow).filter!(a => a.isDir)) {
        foreach(api_file; dirEntries(api, SpanMode.shallow).filter!(a => a.name.endsWith("json"))) {
            generate(api_file);
        }
    }
}
