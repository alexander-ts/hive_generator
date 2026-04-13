import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:hive/hive.dart';
import 'package:hive_generator/src/builder.dart';
import 'package:hive_generator/src/class_builder.dart';
import 'package:hive_generator/src/enum_builder.dart';
import 'package:hive_generator/src/helper.dart';
import 'package:source_gen/source_gen.dart';

class TypeAdapterGenerator extends GeneratorForAnnotation<HiveType> {
  @override
  Future<String> generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) async {
    var cls = getClass(element);
    var gettersAndSetters = getAccessors(cls);

    var getters = gettersAndSetters[0];
    verifyFieldIndices(getters);

    var setters = gettersAndSetters[1];
    verifyFieldIndices(setters);

    var typeId = getTypeId(annotation);

    var adapterName = getAdapterName(cls.name!, annotation);
    var builder = cls is EnumElement
        ? EnumBuilder(cls, getters)
        : ClassBuilder(cls, getters, setters);

    return '''
    class $adapterName extends TypeAdapter<${cls.name!}> {
      @override
      final typeId = $typeId;

      @override
      ${cls.name!} read(BinaryReader reader) {
        ${builder.buildRead()}
      }

      @override
      void write(BinaryWriter writer, ${cls.name!} obj) {
        ${builder.buildWrite()}
      }
    }
    ''';
  }

  InterfaceElement getClass(Element element) {
    check(element is InterfaceElement,
        'Only classes or enums are allowed to be annotated with @HiveType.');

    return element as InterfaceElement;
  }

  List<List<AdapterField>> getAccessors(InterfaceElement cls) {
    var getters = <AdapterField>[];
    var setters = <AdapterField>[];
    var seenNames = <String>{};

    var types = [cls, ...cls.allSupertypes.map((t) => t.element)];

    for (var type in types) {
      for (var field in type.fields) {
        if (field.isStatic && !field.isEnumConstant) continue;
        var fieldName = field.name!;
        if (seenNames.contains(fieldName)) continue;
        seenNames.add(fieldName);

        var ann = getHiveFieldAnn(field);
        if (ann != null) {
          getters.add(AdapterField(ann.index, fieldName, field.type));
          if (!field.isFinal && !field.isConst) {
            setters.add(AdapterField(ann.index, fieldName, field.type));
          }
        }
      }
    }

    return [getters, setters];
  }

  void verifyFieldIndices(List<AdapterField> fields) {
    for (var field in fields) {
      check(field.index >= 0 && field.index <= 255,
          'Field numbers can only be in the range 0-255.');

      for (var otherField in fields) {
        if (otherField == field) continue;
        if (otherField.index == field.index) {
          throw HiveError(
            'Duplicate field number: ${field.index}. Fields "${field.name}" '
            'and "${otherField.name}" have the same number.',
          );
        }
      }
    }
  }

  String getAdapterName(String typeName, ConstantReader annotation) {
    var annAdapterName = annotation.read('adapterName');
    if (annAdapterName.isNull) {
      return '${typeName}Adapter';
    } else {
      return annAdapterName.stringValue;
    }
  }

  int getTypeId(ConstantReader annotation) {
    check(
      !annotation.read('typeId').isNull,
      'You have to provide a non-null typeId.',
    );
    return annotation.read('typeId').intValue;
  }
}