import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartx/dartx.dart';
import 'package:hive_generator/src/builder.dart';
import 'package:hive_generator/src/helper.dart';
import 'package:source_gen/source_gen.dart';

class ClassBuilder extends Builder {
  var hiveListChecker =
      const TypeChecker.fromUrl('package:hive/hive.dart#HiveList');
  var listChecker = const TypeChecker.fromUrl('dart:core#List');
  var mapChecker = const TypeChecker.fromUrl('dart:core#Map');
  var setChecker = const TypeChecker.fromUrl('dart:core#Set');
  var iterableChecker = const TypeChecker.fromUrl('dart:core#Iterable');
  var uint8ListChecker = const TypeChecker.fromUrl('dart:typed_data#Uint8List');

  ClassBuilder(InterfaceElement cls, List<AdapterField> getters,
      List<AdapterField> setters)
      : super(cls, getters, setters);

  @override
  String buildRead() {
    var code = StringBuffer();
    code.writeln('''
    var numOfFields = reader.readByte();
    var fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ${cls.name!}(
    ''');

    // In analyzer 8+, the unnamed constructor name is 'new' (not '').
    var constr = cls.constructors
        .firstOrNullWhere((it) => it.name == 'new' || (it.name ?? '').isEmpty);
    check(constr != null, 'Provide an unnamed constructor.');

    // The remaining fields to initialize.
    var fields = setters.toList();

    var initializingParams =
        constr!.formalParameters.where((param) => param.isInitializingFormal);
    for (var param in initializingParams) {
      var field = fields.firstOrNullWhere((it) => it.name == param.name);
      // Final fields
      field ??= getters.firstOrNullWhere((it) => it.name == param.name);
      if (field != null) {
        if (param.isNamed) {
          code.write('${param.name}: ');
        }
        code.writeln('${_cast(param.type, 'fields[${field.index}]')},');
        fields.remove(field);
      }
    }

    code.writeln(')');

    // There may still be fields to initialize that were not in the constructor
    // as initializing formals. We do so using cascades.
    for (var field in fields) {
      code.writeln(
          '..${field.name} = ${_cast(field.type, 'fields[${field.index}]')}');
    }

    code.writeln(';');

    return code.toString();
  }

  bool _isNullable(DartType type) =>
      type.nullabilitySuffix == NullabilitySuffix.question;

  String _cast(DartType type, String variable) {
    var q = _isNullable(type) ? '?' : '';
    if (hiveListChecker.isExactlyType(type)) {
      return '($variable as HiveList$q)$q.castHiveList()';
    } else if (iterableChecker.isAssignableFromType(type) &&
        !isUint8List(type)) {
      return '($variable as List$q)${_castIterable(type)}';
    } else if (mapChecker.isExactlyType(type)) {
      return '($variable as Map$q)${_castMap(type)}';
    } else {
      return '$variable as ${type.getDisplayString()}';
    }
  }

  bool isMapOrIterable(DartType type) {
    return listChecker.isExactlyType(type) ||
        setChecker.isExactlyType(type) ||
        iterableChecker.isExactlyType(type) ||
        mapChecker.isExactlyType(type);
  }

  bool isUint8List(DartType type) {
    return uint8ListChecker.isExactlyType(type);
  }

  String _castIterable(DartType type) {
    var q = _isNullable(type) ? '?' : '';
    var paramType = type as ParameterizedType;
    var arg = paramType.typeArguments[0];
    if (isMapOrIterable(arg) && !isUint8List(arg)) {
      var toCollection = '';
      if (listChecker.isExactlyType(type)) {
        toCollection = '$q.toList()';
      } else if (setChecker.isExactlyType(type)) {
        toCollection = '$q.toSet()';
      }
      return '$q.map((dynamic e)=> ${_cast(arg, 'e')})$toCollection';
    } else {
      return '$q.cast<${arg.getDisplayString()}>()';
    }
  }

  String _castMap(DartType type) {
    var q = _isNullable(type) ? '?' : '';
    var paramType = type as ParameterizedType;
    var arg1 = paramType.typeArguments[0];
    var arg2 = paramType.typeArguments[1];
    if (isMapOrIterable(arg1) || isMapOrIterable(arg2)) {
      return '$q.map((dynamic k, dynamic v)=>'
          'MapEntry(${_cast(arg1, 'k')},${_cast(arg2, 'v')}))';
    } else {
      return '$q.cast<${arg1.getDisplayString()},'
          ' ${arg2.getDisplayString()}>()';
    }
  }

  @override
  String buildWrite() {
    var code = StringBuffer();
    code.writeln('writer');
    code.writeln('..writeByte(${getters.length})');
    for (var field in getters) {
      var value = _convertIterable(field.type, 'obj.${field.name}');
      code.writeln('''
      ..writeByte(${field.index})
      ..write($value)''');
    }
    code.writeln(';');

    return code.toString();
  }

  String _convertIterable(DartType type, String accessor) {
    if (setChecker.isExactlyType(type) ||
        iterableChecker.isExactlyType(type)) {
      var q = _isNullable(type) ? '?' : '';
      return '$accessor$q.toList()';
    } else {
      return accessor;
    }
  }
}