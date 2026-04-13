import 'package:analyzer/dart/element/element.dart';
import 'package:hive_generator/src/builder.dart';

class EnumBuilder extends Builder {
  EnumBuilder(InterfaceElement cls, List<AdapterField> getters)
      : super(cls, getters, const []);

  @override
  String buildRead() {
    var code = StringBuffer();
    code.writeln('switch(reader.readByte()) {');

    for (var field in getters) {
      code.writeln('''
        case ${field.index}:
          return ${cls.name!}.${field.name};''');
    }

    code.writeln('''
      default:
        throw HiveError('Unknown stored enum index for type ${cls.name!}');
      }''');

    return code.toString();
  }

  @override
  String buildWrite() {
    var code = StringBuffer();
    code.writeln('switch(obj) {');

    for (var field in getters) {
      code.writeln('''
        case ${cls.name!}.${field.name}:
          writer.writeByte(${field.index});
          break;''');
    }

    code.writeln('}');

    return code.toString();
  }
}