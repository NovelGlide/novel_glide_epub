// The navigation (NCX) schema value types — `EpubNavigation` and everything
// under it: head and its meta, docTitle, docAuthors, navMap and its points,
// pageList and its targets, navLists and their targets, plus the shared
// `EpubNavigationLabel` and `EpubNavigationContent`.
//
// Plain data holders, so exercised by direct construction;
// `navigation_reader_*_test.dart` covers how the reader fills them. One
// integration group at the end reads a real NCX through `EpubReader.openBook`
// so the equality contract is checked over reader-produced values too.
//
// This layer carries the package's two documented uninitialised-field defects
// — `EpubNavigationList` and `EpubNavigationTarget` — and this file pins the
// CLASS-side half of each: what the object does once the reader has left those
// fields null. Every such test says so and says what must change when fixed.
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_list.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_list.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_target.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_target_type.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_target.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

EpubNavigationLabel seedLabel([String text = 'NGE-SEED Label']) =>
    EpubNavigationLabel()..text = text;

EpubNavigationContent seedNavContent({
  String? id = 'content-1',
  String? source = 'chapter1.xhtml',
}) =>
    EpubNavigationContent()
      ..id = id
      ..source = source;

EpubNavigationHeadMeta seedHeadMeta({
  String? name = 'dtb:uid',
  String? content = 'urn:uuid:NGE-SEED-NAVSCHEMA',
  String? scheme = 'URN',
}) =>
    EpubNavigationHeadMeta()
      ..name = name
      ..content = content
      ..scheme = scheme;

EpubNavigationHead seedHead({List<EpubNavigationHeadMeta>? metadata}) =>
    EpubNavigationHead()
      ..metadata = metadata ?? <EpubNavigationHeadMeta>[seedHeadMeta()];

EpubNavigationDocTitle seedDocTitle({List<String>? titles}) =>
    EpubNavigationDocTitle()
      ..titles = titles ?? <String>['NGE-SEED Navigation Book'];

EpubNavigationDocAuthor seedDocAuthor({List<String>? authors}) =>
    EpubNavigationDocAuthor()..authors = authors ?? <String>['NGE-SEED Author'];

/// Both list fields assigned, matching what `readNavigationPoint` produces —
/// `EpubNavigationPoint.hashCode` requires them (TC-NSC-3).
EpubNavigationPoint seedPoint({
  String? id = 'np-1',
  String? navClass = 'chapter',
  String? playOrder = '1',
  List<EpubNavigationLabel>? labels,
  EpubNavigationContent? content,
  List<EpubNavigationPoint>? children,
}) =>
    EpubNavigationPoint()
      ..id = id
      ..className = navClass
      ..playOrder = playOrder
      ..navigationLabels = labels ?? <EpubNavigationLabel>[seedLabel()]
      ..content = content ?? seedNavContent()
      ..childNavigationPoints = children ?? <EpubNavigationPoint>[];

EpubNavigationMap seedMap({List<EpubNavigationPoint>? points}) =>
    EpubNavigationMap()..points = points ?? <EpubNavigationPoint>[seedPoint()];

EpubNavigationPageTarget seedPageTarget({
  String? id = 'pt-1',
  String? value = '1',
  EpubNavigationPageTargetType? type = EpubNavigationPageTargetType.normal,
  String? targetClass = 'pagenum',
  String? playOrder = '1',
  List<EpubNavigationLabel>? labels,
  EpubNavigationContent? content,
}) =>
    EpubNavigationPageTarget()
      ..id = id
      ..value = value
      ..type = type
      ..className = targetClass
      ..playOrder = playOrder
      ..navigationLabels = labels ?? <EpubNavigationLabel>[seedLabel()]
      ..content = content ?? seedNavContent();

EpubNavigationPageList seedPageList({
  List<EpubNavigationPageTarget>? targets,
}) =>
    EpubNavigationPageList()
      ..targets = targets ?? <EpubNavigationPageTarget>[seedPageTarget()];

/// `navigationLabels` is assigned here even though `readNavigationTarget`
/// never does — without it the object cannot be hashed at all (TC-NSC-5).
EpubNavigationTarget seedTarget({
  String? id = 'nt-1',
  String? targetClass = 'illustration',
  String? value = 'NGE-SEED Figure 1',
  String? playOrder = '1',
  List<EpubNavigationLabel>? labels,
  EpubNavigationContent? content,
}) =>
    EpubNavigationTarget()
      ..id = id
      ..className = targetClass
      ..value = value
      ..playOrder = playOrder
      ..navigationLabels = labels ?? <EpubNavigationLabel>[seedLabel()]
      ..content = content ?? seedNavContent();

EpubNavigationList seedList({
  String? id = 'nl-1',
  String? listClass = 'illustrations',
  List<EpubNavigationLabel>? labels,
  List<EpubNavigationTarget>? targets,
}) =>
    EpubNavigationList()
      ..id = id
      ..className = listClass
      ..navigationLabels = labels ?? <EpubNavigationLabel>[seedLabel()]
      ..navigationTargets = targets ?? <EpubNavigationTarget>[seedTarget()];

EpubNavigation seedNavigation() => EpubNavigation()
  ..head = seedHead()
  ..docTitle = seedDocTitle()
  ..docAuthors = <EpubNavigationDocAuthor>[seedDocAuthor()]
  ..navMap = seedMap()
  ..pageList = seedPageList()
  ..navLists = <EpubNavigationList>[seedList()];

/// An operand of an unrelated type, held as `Object` so each comparison below
/// is a real runtime check. Typing it `Object` rather than inlining a literal
/// is what keeps these tests free of an `unrelated_type_equality_checks`
/// suppression, which this package's lint forbids outright.
const Object unrelatedOperand = 'NGE-SEED-not-a-domain-object';

/// A null operand, typed nullable so the analyzer does not fold the comparison
/// away as a statically-known mismatch. Every class under test must answer
/// false here rather than throw.
const Object? nullOperand = null;

void main() {
  group('The navigation layer as a whole', () {
    // TC-NSC-1 [Error guessing]: the regression guard for a defect every
    // class in this directory carried except `EpubNavigationContent`.
    // `operator ==` used to open with `other as X?` — a cast — so an unrelated
    // operand threw a `TypeError` where the Dart contract requires `false`.
    // Every class answers false now, which is why `EpubNavigationContent` —
    // the lone counter-example, formerly TC-NSC-2 — is simply a row here.
    for (final MapEntry<String, Object> row in <String, Object>{
      'EpubNavigation': seedNavigation(),
      'EpubNavigationHead': seedHead(),
      'EpubNavigationHeadMeta': seedHeadMeta(),
      'EpubNavigationDocTitle': seedDocTitle(),
      'EpubNavigationDocAuthor': seedDocAuthor(),
      'EpubNavigationLabel': seedLabel(),
      'EpubNavigationContent': seedNavContent(),
      'EpubNavigationMap': seedMap(),
      'EpubNavigationPoint': seedPoint(),
      'EpubNavigationPageList': seedPageList(),
      'EpubNavigationPageTarget': seedPageTarget(),
      'EpubNavigationList': seedList(),
      'EpubNavigationTarget': seedTarget(),
    }.entries) {
      test(
          'TC-NSC-1 [Error guessing]: ${row.key} == an unrelated type '
          'returns false', () {
        expect(row.value == unrelatedOperand, isFalse);
        expect(row.value == nullOperand, isFalse);
      });
    }

    // TC-NSC-3 [Error guessing]: KNOWN DEFECT. `EpubNavigationPoint.hashCode`
    // dereferences both `navigationLabels!` and `childNavigationPoints!`, and
    // `toString` dereferences `content!`, so a bare point is neither hashable
    // nor printable. `readNavigationPoint` assigns all three, which is why the
    // read path never hits this. Pinned as it behaves today.
    test(
        'TC-NSC-3 [Error guessing]: KNOWN DEFECT — a bare EpubNavigationPoint '
        'can be neither hashed nor printed', () {
      expect(() => EpubNavigationPoint().hashCode, throwsA(isA<TypeError>()));
      expect(EpubNavigationPoint().toString, throwsA(isA<TypeError>()));

      // A point missing only `content` still hashes; only `toString` fails.
      final EpubNavigationPoint noContent = seedPoint()..content = null;
      expect(noContent.hashCode, isA<int>());
      expect(noContent.toString, throwsA(isA<TypeError>()));
    });

    // TC-NSC-4 [Error guessing]: `EpubNavigationLabel.toString` used to return
    // `text!`, so a label whose text was never set — a state the NCX reader
    // can produce — could not be printed at all. It now renders as the empty
    // string, and a populated label still renders its text verbatim.
    test(
        'TC-NSC-4 [Error guessing]: a label with no text prints as empty '
        'rather than throwing', () {
      expect(EpubNavigationLabel().toString(), isEmpty);
      expect(seedLabel().toString(), 'NGE-SEED Label');
    });

    // TC-NSC-5 [Error guessing]: KNOWN DEFECT, and the class-side half of the
    // documented `readNavigationTarget` defect. `EpubNavigationTarget` never
    // initialises `navigationLabels`, and its `hashCode` dereferences that
    // field with `!` — so every target the reader produces is unhashable.
    // `==` survives, because `listsEqual` accepts null. Pinned as it behaves
    // today; when the field is initialised, the first expectation becomes a
    // plain `isA<int>()`.
    test(
        'TC-NSC-5 [Error guessing]: KNOWN DEFECT — a target with null '
        'navigationLabels cannot be hashed, though it still compares', () {
      final EpubNavigationTarget bare = EpubNavigationTarget();

      expect(bare.navigationLabels, isNull);
      expect(() => bare.hashCode, throwsA(isA<TypeError>()));
      expect(bare == EpubNavigationTarget(), isTrue);
      expect(bare == seedTarget(), isFalse);
    });

    // TC-NSC-6 [Boundary value]: `EpubNavigationList` is the other documented
    // uninitialised-field defect, but its `hashCode` uses `?? [0]` rather than
    // `!`, so a bare list — exactly what `readNavigationList` produces — DOES
    // hash and DOES compare. The reader's crash therefore comes from the
    // `.add()` calls on those null fields, not from the class. That split is
    // the reason this test is a boundary case and not a defect pin.
    test(
        'TC-NSC-6 [Boundary]: a bare EpubNavigationList hashes and compares '
        'despite its null list fields', () {
      final EpubNavigationList bare = EpubNavigationList();

      expect(bare.navigationLabels, isNull);
      expect(bare.navigationTargets, isNull);
      expect(bare.hashCode, isA<int>());
      expect(bare, equals(EpubNavigationList()));
      expect(bare, isNot(equals(seedList())));
    });

    // TC-NSC-31 [Boundary value]: `EpubNavigationPageTarget` also falls
    // back to `?? [0]` for a null `navigationLabels`, so — unlike the
    // `EpubNavigationTarget` of TC-NSC-5 — a bare page target hashes. The
    // fallback must stay distinct from an empty list's hash: the two targets
    // compare unequal (`listsEqual(null, [])` is false), and a `?? []`
    // "simplification" would make them collide.
    test(
        'TC-NSC-31 [Boundary]: a page target with null navigationLabels '
        'hashes, and differently from one with an empty list', () {
      final EpubNavigationPageTarget bare = EpubNavigationPageTarget();
      final EpubNavigationPageTarget empty = EpubNavigationPageTarget()
        ..navigationLabels = <EpubNavigationLabel>[];

      expect(bare.navigationLabels, isNull);
      expect(bare.hashCode, equals(EpubNavigationPageTarget().hashCode));
      expect(bare.hashCode, isNot(equals(empty.hashCode)));
    });

    // TC-NSC-7 [Scenario/use-case]: every class agrees with its own twin.
    for (final MapEntry<String, List<Object>> row in <String, List<Object>>{
      'EpubNavigation': <Object>[seedNavigation(), seedNavigation()],
      'EpubNavigationHead': <Object>[seedHead(), seedHead()],
      'EpubNavigationHeadMeta': <Object>[seedHeadMeta(), seedHeadMeta()],
      'EpubNavigationDocTitle': <Object>[seedDocTitle(), seedDocTitle()],
      'EpubNavigationDocAuthor': <Object>[seedDocAuthor(), seedDocAuthor()],
      'EpubNavigationLabel': <Object>[seedLabel(), seedLabel()],
      'EpubNavigationContent': <Object>[seedNavContent(), seedNavContent()],
      'EpubNavigationMap': <Object>[seedMap(), seedMap()],
      'EpubNavigationPoint': <Object>[seedPoint(), seedPoint()],
      'EpubNavigationPageList': <Object>[seedPageList(), seedPageList()],
      'EpubNavigationPageTarget': <Object>[seedPageTarget(), seedPageTarget()],
      'EpubNavigationList': <Object>[seedList(), seedList()],
      'EpubNavigationTarget': <Object>[seedTarget(), seedTarget()],
    }.entries) {
      test('TC-NSC-7 [Scenario]: two identical ${row.key} values are equal',
          () {
        expect(row.value[0], equals(row.value[1]));
        expect(row.value[0].hashCode, equals(row.value[1].hashCode));
      });
    }
  });

  group('EpubNavigationLabel / EpubNavigationContent', () {
    // TC-NSC-8 [Equivalence partitioning]: a label is its text.
    test('TC-NSC-8 [Equivalence partitioning]: labels differ by text', () {
      expect(seedLabel(), isNot(equals(seedLabel('NGE-SEED Other'))));
      expect(
        seedLabel().hashCode,
        isNot(equals(seedLabel('NGE-SEED Other').hashCode)),
      );
      expect(EpubNavigationLabel(), equals(EpubNavigationLabel()));
    });

    // TC-NSC-9 [Equivalence partitioning]: both content fields decide.
    for (final MapEntry<String, EpubNavigationContent> row
        in <String, EpubNavigationContent>{
      'id': seedNavContent(id: 'content-2'),
      'source': seedNavContent(source: 'chapter2.xhtml'),
    }.entries) {
      test(
          'TC-NSC-9 [Equivalence partitioning]: content with a differing '
          '${row.key} is unequal', () {
        expect(seedNavContent(), isNot(equals(row.value)));
        expect(seedNavContent().hashCode, isNot(equals(row.value.hashCode)));
      });
    }

    // TC-NSC-10 [Scenario/use-case]: content renders its source only — the id
    // is deliberately absent from `toString`.
    test('TC-NSC-10 [Scenario]: content renders its source', () {
      expect(seedNavContent().toString(), 'Source: chapter1.xhtml');
      expect(EpubNavigationContent().toString(), 'Source: null');
    });
  });

  group('EpubNavigationHead / EpubNavigationHeadMeta', () {
    // TC-NSC-11 [Equivalence partitioning]: all three meta fields decide.
    for (final MapEntry<String, EpubNavigationHeadMeta> row
        in <String, EpubNavigationHeadMeta>{
      'name': seedHeadMeta(name: 'dtb:depth'),
      'content': seedHeadMeta(content: 'urn:uuid:NGE-SEED-OTHER'),
      'scheme': seedHeadMeta(scheme: 'ISBN'),
    }.entries) {
      test(
          'TC-NSC-11 [Equivalence partitioning]: head meta with a differing '
          '${row.key} is unequal', () {
        expect(seedHeadMeta(), isNot(equals(row.value)));
        expect(seedHeadMeta().hashCode, isNot(equals(row.value.hashCode)));
      });
    }

    // TC-NSC-12 [Boundary value]: the head's constructor initialises its list,
    // so an empty head hashes — and differs from a populated one.
    test('TC-NSC-12 [Boundary]: an empty head hashes and differs', () {
      expect(EpubNavigationHead().metadata, isEmpty);
      expect(EpubNavigationHead().hashCode, isA<int>());
      expect(EpubNavigationHead(), equals(EpubNavigationHead()));
      expect(EpubNavigationHead(), isNot(equals(seedHead())));
    });

    // TC-NSC-13 [Equivalence partitioning]: the head compares its metadata
    // element-wise, so both count and content decide.
    test('TC-NSC-13 [Equivalence partitioning]: heads differ by metadata list',
        () {
      expect(
        seedHead(),
        isNot(
          equals(
            seedHead(
              metadata: <EpubNavigationHeadMeta>[
                seedHeadMeta(),
                seedHeadMeta(name: 'dtb:depth'),
              ],
            ),
          ),
        ),
      );
    });
  });

  group('EpubNavigationDocTitle / EpubNavigationDocAuthor', () {
    // TC-NSC-14 [Equivalence partitioning]: both are thin list wrappers whose
    // constructors initialise the list.
    test('TC-NSC-14 [Equivalence partitioning]: doc titles differ by titles',
        () {
      expect(EpubNavigationDocTitle().titles, isEmpty);
      expect(EpubNavigationDocTitle().hashCode, isA<int>());
      expect(seedDocTitle(), isNot(equals(EpubNavigationDocTitle())));
      expect(
        seedDocTitle(),
        isNot(equals(seedDocTitle(titles: <String>['NGE-SEED Other']))),
      );
    });

    test('TC-NSC-14 [Equivalence partitioning]: doc authors differ by authors',
        () {
      expect(EpubNavigationDocAuthor().authors, isEmpty);
      expect(EpubNavigationDocAuthor().hashCode, isA<int>());
      expect(seedDocAuthor(), isNot(equals(EpubNavigationDocAuthor())));
      expect(
        seedDocAuthor(),
        isNot(equals(seedDocAuthor(authors: <String>['NGE-SEED Other']))),
      );
    });

    // TC-NSC-15 [Boundary value]: a multi-entry docTitle is legal NCX (one
    // `<text>` per language) and is compared element-wise, order included.
    test('TC-NSC-15 [Boundary]: doc title order is significant', () {
      expect(
        seedDocTitle(titles: <String>['NGE-SEED A', 'NGE-SEED B']),
        isNot(
            equals(seedDocTitle(titles: <String>['NGE-SEED B', 'NGE-SEED A']))),
      );
    });
  });

  group('EpubNavigationMap / EpubNavigationPoint', () {
    // TC-NSC-16 [Equivalence partitioning]: all six point fields decide.
    for (final MapEntry<String, EpubNavigationPoint> row
        in <String, EpubNavigationPoint>{
      'id': seedPoint(id: 'np-2'),
      'className': seedPoint(navClass: 'section'),
      'playOrder': seedPoint(playOrder: '2'),
      'navigationLabels': seedPoint(
        labels: <EpubNavigationLabel>[seedLabel('NGE-SEED Other')],
      ),
      'content': seedPoint(content: seedNavContent(source: 'chapter2.xhtml')),
      'childNavigationPoints': seedPoint(
        children: <EpubNavigationPoint>[seedPoint(id: 'np-1-1')],
      ),
    }.entries) {
      test(
          'TC-NSC-16 [Equivalence partitioning]: a point with a differing '
          '${row.key} is unequal', () {
        expect(seedPoint(), isNot(equals(row.value)));
        expect(seedPoint().hashCode, isNot(equals(row.value.hashCode)));
      });
    }

    // TC-NSC-17 [Scenario/use-case]: a point renders its id and its content
    // source — the shape the NCX walk debug-prints.
    test('TC-NSC-17 [Scenario]: a point renders its id and content source', () {
      expect(
        seedPoint().toString(),
        'Id: np-1, Content.Source: chapter1.xhtml',
      );
    });

    // TC-NSC-18 [Scenario/use-case]: nesting is compared recursively, to
    // arbitrary depth.
    test('TC-NSC-18 [Scenario]: nested points compare recursively', () {
      EpubNavigationPoint tree(String leafId) => seedPoint(
            children: <EpubNavigationPoint>[
              seedPoint(
                id: 'np-1-1',
                children: <EpubNavigationPoint>[seedPoint(id: leafId)],
              ),
            ],
          );

      expect(tree('np-1-1-1'), equals(tree('np-1-1-1')));
      expect(tree('np-1-1-1').hashCode, equals(tree('np-1-1-1').hashCode));
      expect(tree('np-1-1-1'), isNot(equals(tree('np-1-1-2'))));
    });

    // TC-NSC-19 [Boundary value]: `EpubNavigationMap` has no constructor, so
    // `points` starts null — and unlike the point itself, the map survives it
    // through `?? [0]`.
    test('TC-NSC-19 [Boundary]: a map with null points hashes and compares',
        () {
      expect(EpubNavigationMap().points, isNull);
      expect(EpubNavigationMap().hashCode, isA<int>());
      expect(EpubNavigationMap(), equals(EpubNavigationMap()));
      expect(EpubNavigationMap(), isNot(equals(seedMap())));
      expect(
        seedMap(points: <EpubNavigationPoint>[]),
        isNot(equals(EpubNavigationMap())),
      );
    });
  });

  group('EpubNavigationPageList / EpubNavigationPageTarget', () {
    // TC-NSC-20 [Equivalence partitioning]: all seven page-target fields.
    for (final MapEntry<String, EpubNavigationPageTarget> row
        in <String, EpubNavigationPageTarget>{
      'id': seedPageTarget(id: 'pt-2'),
      'value': seedPageTarget(value: '2'),
      'type': seedPageTarget(type: EpubNavigationPageTargetType.front),
      'className': seedPageTarget(targetClass: 'other'),
      'playOrder': seedPageTarget(playOrder: '2'),
      'content': seedPageTarget(
        content: seedNavContent(source: 'chapter2.xhtml'),
      ),
      'navigationLabels': seedPageTarget(
        labels: <EpubNavigationLabel>[seedLabel('NGE-SEED Other')],
      ),
    }.entries) {
      test(
          'TC-NSC-20 [Equivalence partitioning]: a page target with a '
          'differing ${row.key} is unequal', () {
        expect(seedPageTarget(), isNot(equals(row.value)));
        expect(seedPageTarget().hashCode, isNot(equals(row.value.hashCode)));
      });
    }

    // TC-NSC-21 [Boundary value]: all four enum values are distinct operands,
    // and `undefined` is the reader's fallback for an unrecognised `type`.
    test('TC-NSC-21 [Boundary]: every page-target type is distinguished', () {
      expect(EpubNavigationPageTargetType.values, hasLength(4));
      for (final EpubNavigationPageTargetType type
          in EpubNavigationPageTargetType.values) {
        for (final EpubNavigationPageTargetType other
            in EpubNavigationPageTargetType.values) {
          expect(
            seedPageTarget(type: type) == seedPageTarget(type: other),
            type == other,
          );
        }
      }
      expect(seedPageTarget(type: null), isNot(equals(seedPageTarget())));
    });

    // TC-NSC-22 [Boundary value]: the page list has no constructor either, so
    // null targets are its initial state.
    test('TC-NSC-22 [Boundary]: a page list with null targets hashes', () {
      expect(EpubNavigationPageList().targets, isNull);
      expect(EpubNavigationPageList().hashCode, isA<int>());
      expect(EpubNavigationPageList(), equals(EpubNavigationPageList()));
      expect(EpubNavigationPageList(), isNot(equals(seedPageList())));
    });
  });

  group('EpubNavigationList / EpubNavigationTarget', () {
    // TC-NSC-23 [Equivalence partitioning]: all six target fields decide.
    // `navigationLabels` is checked last, after the five scalars short-circuit.
    for (final MapEntry<String, EpubNavigationTarget> row
        in <String, EpubNavigationTarget>{
      'id': seedTarget(id: 'nt-2'),
      'className': seedTarget(targetClass: 'table'),
      'value': seedTarget(value: 'NGE-SEED Figure 2'),
      'playOrder': seedTarget(playOrder: '2'),
      'content': seedTarget(content: seedNavContent(source: 'chapter2.xhtml')),
      'navigationLabels': seedTarget(
        labels: <EpubNavigationLabel>[seedLabel('NGE-SEED Other')],
      ),
    }.entries) {
      test(
          'TC-NSC-23 [Equivalence partitioning]: a target with a differing '
          '${row.key} is unequal', () {
        expect(seedTarget(), isNot(equals(row.value)));
        expect(seedTarget().hashCode, isNot(equals(row.value.hashCode)));
      });
    }

    // TC-NSC-24 [Equivalence partitioning]: all four navList fields decide.
    for (final MapEntry<String, EpubNavigationList> row
        in <String, EpubNavigationList>{
      'id': seedList(id: 'nl-2'),
      'className': seedList(listClass: 'tables'),
      'navigationLabels': seedList(
        labels: <EpubNavigationLabel>[seedLabel('NGE-SEED Other')],
      ),
      'navigationTargets': seedList(
        targets: <EpubNavigationTarget>[seedTarget(id: 'nt-2')],
      ),
    }.entries) {
      test(
          'TC-NSC-24 [Equivalence partitioning]: a navList with a differing '
          '${row.key} is unequal', () {
        expect(seedList(), isNot(equals(row.value)));
        expect(seedList().hashCode, isNot(equals(row.value.hashCode)));
      });
    }

    // TC-NSC-25 [Boundary value]: a null list field and an assigned-but-empty
    // one are DIFFERENT operands to `listsEqual`, which is what separates the
    // reader's broken state (null) from a legitimately empty navList.
    test('TC-NSC-25 [Boundary]: null list fields differ from empty ones', () {
      final EpubNavigationList empty = seedList(
        labels: <EpubNavigationLabel>[],
        targets: <EpubNavigationTarget>[],
      );

      expect(empty, isNot(equals(EpubNavigationList()..id = 'nl-1')));
      expect(
        empty,
        equals(
          seedList(
            labels: <EpubNavigationLabel>[],
            targets: <EpubNavigationTarget>[],
          ),
        ),
      );
    });
  });

  group('EpubNavigation', () {
    // TC-NSC-26 [Equivalence partitioning]: all six fields decide. `docAuthors`
    // and `navLists` are checked before the four scalars, so each gets a row.
    for (final MapEntry<String, EpubNavigation Function(EpubNavigation)> row
        in <String, EpubNavigation Function(EpubNavigation)>{
      'head': (EpubNavigation n) => n
        ..head = seedHead(
          metadata: <EpubNavigationHeadMeta>[seedHeadMeta(name: 'dtb:depth')],
        ),
      'docTitle': (EpubNavigation n) =>
          n..docTitle = seedDocTitle(titles: <String>['NGE-SEED Other']),
      'docAuthors': (EpubNavigation n) => n
        ..docAuthors = <EpubNavigationDocAuthor>[
          seedDocAuthor(authors: <String>['NGE-SEED Other']),
        ],
      'navMap': (EpubNavigation n) => n
        ..navMap =
            seedMap(points: <EpubNavigationPoint>[seedPoint(id: 'np-2')]),
      'pageList': (EpubNavigation n) => n
        ..pageList = seedPageList(
          targets: <EpubNavigationPageTarget>[seedPageTarget(id: 'pt-2')],
        ),
      'navLists': (EpubNavigation n) =>
          n..navLists = <EpubNavigationList>[seedList(id: 'nl-2')],
    }.entries) {
      test(
          'TC-NSC-26 [Equivalence partitioning]: a navigation with a '
          'differing ${row.key} is unequal', () {
        final EpubNavigation other = row.value(seedNavigation());

        expect(seedNavigation(), isNot(equals(other)));
        expect(seedNavigation().hashCode, isNot(equals(other.hashCode)));
      });
    }

    // TC-NSC-27 [Boundary value]: an all-null navigation is what an EPUB3
    // book with neither NCX nor nav document leaves behind, and it hashes
    // through the two `?? [0]` fallbacks.
    test('TC-NSC-27 [Boundary]: an all-null navigation hashes and compares',
        () {
      expect(EpubNavigation().hashCode, isA<int>());
      expect(EpubNavigation(), equals(EpubNavigation()));
      expect(EpubNavigation(), isNot(equals(seedNavigation())));
    });

    // TC-NSC-28 [Boundary value]: null and empty `docAuthors` / `navLists` are
    // distinct, mirroring TC-NSC-25 one level up.
    test('TC-NSC-28 [Boundary]: null and empty author/navList lists differ',
        () {
      final EpubNavigation empty = EpubNavigation()
        ..docAuthors = <EpubNavigationDocAuthor>[]
        ..navLists = <EpubNavigationList>[];

      expect(empty, isNot(equals(EpubNavigation())));
      expect(
        empty,
        equals(
          EpubNavigation()
            ..docAuthors = <EpubNavigationDocAuthor>[]
            ..navLists = <EpubNavigationList>[],
        ),
      );
    });
  });

  group('Navigation schema as produced by EpubReader.openBook', () {
    const String opf = '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
        'unique-identifier="uid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>NGE-SEED Navigation Book</dc:title>'
        '</metadata>'
        '<manifest>'
        '<item id="ncx" href="toc.ncx" '
        'media-type="application/x-dtbncx+xml"/>'
        '<item id="ch1" href="chapter1.xhtml" '
        'media-type="application/xhtml+xml"/>'
        '</manifest>'
        '<spine toc="ncx"><itemref idref="ch1"/></spine>'
        '</package>';

    String ncx(String leafTitle) => '<?xml version="1.0" encoding="UTF-8"?>'
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
        '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-NAVSCHEMA"/>'
        '</head>'
        '<docTitle><text>NGE-SEED Navigation Book</text></docTitle>'
        '<docAuthor><text>NGE-SEED Author</text></docAuthor>'
        '<navMap>'
        '<navPoint id="np-1" class="chapter" playOrder="1">'
        '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
        '<content src="chapter1.xhtml"/>'
        '<navPoint id="np-1-1" class="section" playOrder="2">'
        '<navLabel><text>$leafTitle</text></navLabel>'
        '<content src="chapter1.xhtml#s1"/>'
        '</navPoint>'
        '</navPoint>'
        '</navMap>'
        '<pageList>'
        '<pageTarget id="pt-1" value="1" type="normal" playOrder="1">'
        '<navLabel><text>NGE-SEED Page 1</text></navLabel>'
        '<content src="chapter1.xhtml"/>'
        '</pageTarget>'
        '</pageList>'
        '</ncx>';

    Uint8List build(String leafTitle) => buildEpubArchive(
          opfPath: 'OEBPS/content.opf',
          textEntries: <String, String>{
            'OEBPS/content.opf': opf,
            'OEBPS/toc.ncx': ncx(leafTitle),
            'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
          },
        );

    // TC-NSC-29 [Scenario/use-case]: the reader-produced navigation graph
    // satisfies the equality contract end to end — two reads of one archive
    // agree on `==` and `hashCode` all the way down, which is the property the
    // hand-built cases above assume but cannot demonstrate.
    test(
        'TC-NSC-29 [Scenario]: two reads of one NCX yield equal navigation '
        'graphs', () async {
      final EpubBookRef first =
          await const EpubReader().openBook(build('NGE-SEED S1'));
      final EpubBookRef second =
          await const EpubReader().openBook(build('NGE-SEED S1'));

      final EpubNavigation a = first.schema!.navigation!;
      final EpubNavigation b = second.schema!.navigation!;

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.head, equals(b.head));
      expect(a.docTitle, equals(b.docTitle));
      expect(a.docAuthors, equals(b.docAuthors));
      expect(a.navMap, equals(b.navMap));
      expect(a.pageList, equals(b.pageList));

      // The graph really is populated, so the equality above is not vacuous.
      expect(a.docTitle!.titles, <String>['NGE-SEED Navigation Book']);
      expect(a.navMap!.points, hasLength(1));
      expect(a.navMap!.points!.single.childNavigationPoints, hasLength(1));
      expect(a.pageList!.targets, hasLength(1));
      expect(
        a.pageList!.targets!.single.type,
        EpubNavigationPageTargetType.normal,
      );
      expect(a.navLists, isEmpty);
    });

    // TC-NSC-30 [Equivalence partitioning]: a change buried two levels deep —
    // a nested navPoint's label — propagates up to `EpubNavigation.==`, so the
    // recursive comparison is load-bearing over reader output.
    test(
        'TC-NSC-30 [Equivalence partitioning]: a nested label change makes '
        'the graphs unequal', () async {
      final EpubBookRef first =
          await const EpubReader().openBook(build('NGE-SEED S1'));
      final EpubBookRef second =
          await const EpubReader().openBook(build('NGE-SEED S2'));

      final EpubNavigation a = first.schema!.navigation!;
      final EpubNavigation b = second.schema!.navigation!;

      expect(a, isNot(equals(b)));
      expect(a.navMap, isNot(equals(b.navMap)));
      expect(a.docTitle, equals(b.docTitle));
      expect(
        a.navMap!.points!.single.childNavigationPoints!.single.navigationLabels!
            .single.text,
        'NGE-SEED S1',
      );
    });
  });
}
