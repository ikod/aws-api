import std.stdio;
import std.json;
import std.array;
import std.algorithm;
import std.datetime;
import std.string;
import std.file;
import std.path;

import std.experimental.logger;

enum ShapeRole {
    NOIO_SHAPE = 0, // this shape is not Input or Output shape
    IN_SHAPE = 1,   // Input (argument to operation)
    OUT_SHAPE = 2   // Output (result from operation)
};

void processShape(string name, JSONValue shape, File output, JSONValue shapes, ShapeRole shape_role) {
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

    void processStructure(JSONValue data, ShapeRole role) {
        JSONValue[string] members = data.object["members"].object;
        string[string]    member_types;

        foreach(k,v; members) {
            member_types[k] = v.object["shape"].str ~ "_Type";
        }
        output.writefln("struct %s_Type {", name);

        auto required = "required" in data.object;

        if ( member_types.length ) {
            output.writefln("    alias Values = Variant;", member_types.values.join(", "));
            output.writeln( "    Values[string] dict;");
            if ( role == ShapeRole.IN_SHAPE ) {
                output.writeln( "    string serialize(string memberName) {");
                output.writeln( "        switch(memberName) {");
                foreach(k,v; members) {
                    v.object.remove("documentation");
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
            }
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

        data.object.remove("documentation");

        output.writefln("    string descriptor = `%s`;", data.toJSON(true));
        if ( role == ShapeRole.OUT_SHAPE || role == ShapeRole.NOIO_SHAPE ) {
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
        }
        output.writeln("}");
        output.writeln();
    }

    string shapeType = shape.object["type"].str;
    switch(shapeType) {
        case "structure":
            processStructure(shape, shape_role);
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
            processType!long(shape);
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

void processOperation(string api_name, string name, JSONValue data, JSONValue shapes, File o, string protocol) {

    data.object.remove("documentation");

    string outputType = "output" in data.object ?
                            data.object["output"].object["shape"].str
                            : null;
    string inputType = "input" in data.object ?
                            data.object["input"].object["shape"].str
                            : null;
    string payloadMemberName, outPayloadType, inPayloadType;
    bool   outPayloadStreaming, inPayloadStreaming;
    if ( inputType ) {
        auto input_descriptor = shapes.object[inputType].object;
        auto have_payload = "payload" in input_descriptor;
        if ( have_payload ) {
            payloadMemberName = (*have_payload).str;
            auto payload_descriptor = input_descriptor["members"].object[payloadMemberName].object;
            if ( "streaming" in payload_descriptor ) {
                inPayloadStreaming = true;
            }
            auto payload_shape_name = "shape" in payload_descriptor;
            auto payload_shape = shapes.object[(*payload_shape_name).str].object;
            inPayloadType = payload_shape["type"].str;
            writefln("proto: %s, inpuType: %s, payloadType: %s, streaming: %s", protocol, inputType, inPayloadType, inPayloadStreaming);
        }
    }
    if ( outputType ) {
        //
        // shoud we return structure or blob or stream ?
        //
        auto output_descriptor = shapes.object[outputType].object;
        auto payload_member_name = "payload" in output_descriptor;
        if ( payload_member_name ) {
            //
            // Paylod is what we have to return to user
            // there is three types of payload
            // "blob" - can be "stream" or not
            // "string"
            // "structure"
            //
            payloadMemberName = (*payload_member_name).str;
            auto payload_descriptor = output_descriptor["members"].object[(*payload_member_name).str].object;
            if ( "streaming" in payload_descriptor ) {
                outPayloadStreaming = true;
            }
            auto payload_shape_name = "shape" in payload_descriptor;
            auto payload_shape = shapes.object[(*payload_shape_name).str].object;
            outPayloadType = payload_shape["type"].str;
        }
    }
    if ( inputType ) {
        if ( inPayloadType == "blob" ) {
            o.writefln("auto %s(T)(%s_config config, %s_Type input, T payload) {", name, api_name, inputType);
        } else {
            o.writefln("auto %s(%s_config config, %s_Type input) {", name, api_name, inputType);
        }
    } else {
        o.writefln("auto %s(%s_config config) {", name, api_name);
    }

    o.writefln("    string descriptor = `%s`;", data.toJSON(true).splitLines.map!(s => "    " ~ s).join("\n"));
    o.writeln( "    int retries;");
    o.writeln( "  start:");
    if ( inputType ) {
        o.writefln(`    auto sr = serializeRequest!%s_Type(input, fastParseJSON(descriptor).object);`, inputType);
    } else {
        o.writefln(`    auto sr = serializeRequest(fastParseJSON(descriptor).object);`);
    }

    o.writeln("    string         method = sr.method;");
    o.writeln("    string         requestUri = sr.requestUri;");
    o.writeln("    string[string] headers = sr.headers;");
    o.writeln("    string[]       query = sr.query;");
    //o.writeln("    ubyte[]        payload = sr.payload;");
    o.writeln("    bool           outStreaming = ", outPayloadStreaming, ";");

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

    });
    //
    // handle payload attached to request
    // usecase s3:PutObject
    // we send payload as stream, from aything which can be
    // considered as ubyte[][] range
    //

    if ( inPayloadType == "blob" ) {
    o.writeln(q{
    // we send some blob with request as payload
    args.payload = "UNSIGNED-PAYLOAD".representation;
    auto h = signV4(args);
    foreach(k,v; h) {
        headers[k] = v;
    }
    auto r = drivers.exec(args, headers, outStreaming, payload);
    });
    } else
    if ( inPayloadType == "structure" ) {
    o.writeln(q{
    // we send some structure with request as payload
    //args.payload = "UNSIGNED-PAYLOAD".representation;
    auto h = signV4(args);
    foreach(k,v; h) {
        headers[k] = v;
    }
    auto r = drivers.exec(args, headers, outStreaming, args.payload);
    });

    } else {
    // there is no payload
    o.writeln(q{
    auto h = signV4(args);
    foreach(k,v; h) {
        headers[k] = v;
    }
    auto r = drivers.exec(args, headers, outStreaming);
    });
    }
    // payload processed

    //
    // handle errors
    //
    switch(protocol) {
    case "rest-xml":
    o.writeln(q{
    if ( r.code != 200 ) {
        if ( r.code == 301 ) {
            import std.stdio;
            auto redirect = handleRedirect(r, config, descriptor);
            if ( redirect.ok && retries++ < 3) {
                config = redirect.config;
                goto start;
            }
            writeln(redirect);
            throw new APIException(r.code, "Cant't handle redirect");
        }
        auto error_code = getXMLErrorCode(cast(string)r.responseBody.data);
        throw new APIException(r.code, error_code);
    }
    });
        break;
    default:
        break;
    }
    // errors processed

    //
    // pass output to user
    //
    if ( outputType !is null ) {
        switch (protocol) {
        case "rest-xml":
            if ( outPayloadStreaming ) {
                o.writeln("    auto result = r.receiveAsRange();");
                break;
            }
            switch(outPayloadType) {
            case "blob":
                o.writefln("    auto result = RESTXMLReplyBlob(r.responseBody.data);\n");
                break;
            case "string":
                o.writefln("    auto result = RESTXMLReplyString(r.responseBody.data);\n");
                break;
            default:
                o.writeln( "    string rbody = cast(string)r.responseBody;");
                o.writefln("    %s_Type result;", outputType);
                o.writeln( "    if ( rbody && rbody.length ) {");
                o.writefln("        auto xml = new Document(rbody);\n");
                o.writefln("        result = RESTXMLReply!%s_Type(xml);\n", outputType);
                o.writefln("    } else {");
                o.writefln("        result = %s_Type();", outputType);
                o.writefln("    }");
                break;
            }
            break;
        case "ec2":
            o.writefln(
            "    auto xml = new Document(cast(string)r.responseBody);\n" ~
            "    auto result = %s_Type(xml);\n", outputType);
            break;
        default:
            break;
        }
        o.writefln("    return result;");
    }

    o.writefln("}\n");
}

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

    string api_version = metadata.object["apiVersion"].str;
    string protocol = metadata.object["protocol"].str;
    output.writefln(q{immutable private string api_version = "%s";}.format(api_version));
    output.writefln(q{immutable private string protocol = "%s";}.format(protocol));
    output.writeln();

    ShapeRole[string] shape_roles;

    foreach(op, data; operations.object)
    {
        ShapeRole role;
        auto i = "input" in data;
        auto o = "output" in data;
        if ( i ) {
            shape_roles[(*i).object["shape"].str] = ShapeRole.IN_SHAPE;
        }
        if ( o ) {
            shape_roles[(*o).object["shape"].str] = ShapeRole.OUT_SHAPE;
        }

        processOperation(api_name, op, data, shapes, output, protocol);
    }
    foreach(name, data; shapes.object)
    {
        auto shape_role = shape_roles.get(name, ShapeRole.NOIO_SHAPE);
        processShape(name, data, output, shapes, shape_role);
    }
    output.close();
}

void main()
{
    foreach (string api; dirEntries("apis", SpanMode.shallow).filter!(a => a.isDir))
    {
        foreach(api_file; dirEntries(api, SpanMode.shallow).filter!(a => a.name.endsWith("json")))
        {
            generate(api_file);
        }
    }
}
