// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library bazel_test;

import 'package:protoc_plugin/bazel.dart';
import 'package:test/test.dart';

void main() {
  group('BazelOptionParser', () {
    var optionParser;
    Map<String, BazelPackage> packages;
    var errors;

    setUp(() {
      packages = {};
      optionParser = new BazelOptionParser(packages);
      errors = [];
    });

    _onError(String message) {
      errors.add(message);
    }

    test('should call onError for null values', () {
      optionParser.parse(null, null, _onError);
      expect(errors, isNotEmpty);
    });

    test('should call onError for empty values', () {
      optionParser.parse(null, '', _onError);
      expect(errors, isNotEmpty);
    });

    test('should call onError for malformed entries', () {
      optionParser.parse(null, 'foo', _onError);
      optionParser.parse(null, 'foo|bar', _onError);
      optionParser.parse(null, 'foo|bar|baz|quux', _onError);
      expect(errors.length, 3);
      expect(packages, isEmpty);
    });

    test('should handle a single package|path entry', () {
      optionParser.parse(null, 'foo|bar/baz|wibble/wobble', _onError);
      expect(errors, isEmpty);
      expect(packages.length, 1);
      expect(packages['bar/baz'].name, 'foo');
      expect(packages['bar/baz'].input_root, 'bar/baz');
      expect(packages['bar/baz'].output_root, 'wibble/wobble');
    });

    test('should handle multiple package|path entries', () {
      optionParser.parse(
          null,
          'foo|bar/baz|wibble/wobble;a|b/c/d|e/f;one.two|three|four/five',
          _onError);
      expect(errors, isEmpty);
      expect(packages.length, 3);
      expect(packages['bar/baz'].name, 'foo');
      expect(packages['bar/baz'].input_root, 'bar/baz');
      expect(packages['bar/baz'].output_root, 'wibble/wobble');
      expect(packages['b/c/d'].name, 'a');
      expect(packages['b/c/d'].input_root, 'b/c/d');
      expect(packages['b/c/d'].output_root, 'e/f');
      expect(packages['three'].name, 'one.two');
      expect(packages['three'].input_root, 'three');
      expect(packages['three'].output_root, 'four/five');
    });

    test('should skip and continue past malformed entries', () {
      optionParser.parse(null,
          'foo|bar/baz|wibble/wobble;fizz;a.b|c/d|e/f;x|y|zz|y', _onError);
      expect(errors.length, 2);
      expect(packages.length, 2);
      expect(packages['bar/baz'].name, 'foo');
      expect(packages['c/d'].name, 'a.b');
    });

    test('should emit error for conflicting package names', () {
      optionParser.parse(null,
          'foo|bar/baz|wibble/wobble;flob|bar/baz|wibble/wobble', _onError);
      expect(errors.length, 1);
      expect(packages.length, 1);
      expect(packages['bar/baz'].name, 'foo');
    });

    test('should emit error for conflicting output_roots', () {
      optionParser.parse(null,
          'foo|bar/baz|wibble/wobble;foo|bar/baz|womble/wumble', _onError);
      expect(errors.length, 1);
      expect(packages.length, 1);
      expect(packages['bar/baz'].output_root, 'wibble/wobble');
    });

    test('should normalize paths', () {
      optionParser.parse(
          null, 'foo|bar//baz/|quux/;a|b/|c;c|d//e/f///|g//h//', _onError);
      expect(errors, isEmpty);
      expect(packages.length, 3);
      expect(packages['bar/baz'].name, 'foo');
      expect(packages['bar/baz'].input_root, 'bar/baz');
      expect(packages['bar/baz'].output_root, 'quux');
      expect(packages['b'].name, 'a');
      expect(packages['b'].input_root, 'b');
      expect(packages['b'].output_root, 'c');
      expect(packages['d/e/f'].name, 'c');
      expect(packages['d/e/f'].input_root, 'd/e/f');
      expect(packages['d/e/f'].output_root, 'g/h');
    });
  });

  group('BazelOutputConfiguration', () {
    Map<String, BazelPackage> packages;
    var config;

    setUp(() {
      packages = {
        'foo/bar': new BazelPackage('a.b.c', 'foo/bar', 'baz/flob'),
        'foo/bar/baz': new BazelPackage('d.e.f', 'foo/bar/baz', 'baz/flob/foo'),
        'wibble/wobble':
            new BazelPackage('wibble.wobble', 'wibble/wobble', 'womble/wumble'),
      };
      config = new BazelOutputConfiguration(packages);
    });

    group('outputPathForUri', () {
      test('should handle files at package root', () {
        var p = config.outputPathFor(Uri.parse('foo/bar/quux.proto'));
        expect(p.path, 'baz/flob/quux.pb.dart');
      });

      test('should handle files below package root', () {
        var p = config.outputPathFor(Uri.parse('foo/bar/a/b/quux.proto'));
        expect(p.path, 'baz/flob/a/b/quux.pb.dart');
      });

      test('should handle files in a nested package root', () {
        var p = config.outputPathFor(Uri.parse('foo/bar/baz/quux.proto'));
        expect(p.path, 'baz/flob/foo/quux.pb.dart');
      });

      test('should handle files below a nested package root', () {
        var p = config.outputPathFor(Uri.parse('foo/bar/baz/a/b/quux.proto'));
        expect(p.path, 'baz/flob/foo/a/b/quux.pb.dart');
      });

      test('should throw if unable to locate the package for an input', () {
        expect(
            () => config.outputPathFor(Uri.parse('a/b/c/quux.proto')), throws);
      });
    });

    group('resolveImport', () {
      test('should emit relative import if in same package', () {
        var target = Uri.parse('foo/bar/quux.proto');
        var source = Uri.parse('foo/bar/baz.proto');
        var uri = config.resolveImport(target, source);
        expect(uri.path, 'quux.pb.dart');
      });

      test('should emit relative import if in subdir of same package', () {
        var target = Uri.parse('foo/bar/a/b/quux.proto');
        var source = Uri.parse('foo/bar/baz.proto');
        var uri = config.resolveImport(target, source);
        expect(uri.path, 'a/b/quux.pb.dart');
      });

      test('should emit relative import if in parent dir in same package', () {
        var target = Uri.parse('foo/bar/quux.proto');
        var source = Uri.parse('foo/bar/a/b/baz.proto');
        var uri = config.resolveImport(target, source);
        expect(uri.path, '../../quux.pb.dart');
      });

      test('should emit package: import if in different package', () {
        var target = Uri.parse('wibble/wobble/quux.proto');
        var source = Uri.parse('foo/bar/baz.proto');
        var uri = config.resolveImport(target, source);
        expect(uri.scheme, 'package');
        expect(uri.path, 'wibble.wobble/quux.pb.dart');
      });

      test('should emit package: import if in subdir of different package', () {
        var target = Uri.parse('wibble/wobble/foo/bar/quux.proto');
        var source = Uri.parse('foo/bar/baz.proto');
        var uri = config.resolveImport(target, source);
        expect(uri.scheme, 'package');
        expect(uri.path, 'wibble.wobble/foo/bar/quux.pb.dart');
      });

      test('should throw if target is in unknown package', () {
        var target = Uri.parse('flob/flub/quux.proto');
        var source = Uri.parse('foo/bar/baz.proto');
        expect(() => config.resolveImport(target, source), throws);
      });
    });
  });
}
