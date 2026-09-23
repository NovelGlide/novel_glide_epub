// The navigation (NCX) schema value types — `EpubNavigation` and everything
// under it: head and its meta, docTitle, docAuthors, navMap and its points,
// pageList and its targets, navLists and their targets, plus the shared
// `EpubNavigationLabel` and `EpubNavigationContent`.
//
// Immutable data holders, so exercised by direct construction;
// `navigation_reader_*_test.dart` covers how the reader fills them. One
// integration group at the end reads a real NCX through `EpubReader.openBook`
// so the equality contract is checked over reader-produced values too.
//
// Every field of every class gets a one-field-at-a-time partition row that
// checks `==` AND `hashCode`, so dropping any clause of either is caught. A
// field the NCX makes optional is nullable, and TC-NSC-32 pins that a null
// there is a value of its own.
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
    EpubNavigationLabel(text: text);

EpubNavigationContent seedNavContent({
  String? id = 'content-1',
  String? source = 'chapter1.xhtml',
}) =>
    EpubNavigationContent(id: id, source: source);

EpubNavigationHeadMeta seedHeadMeta({
  String name = 'dtb:uid',
  String content = 'urn:uuid:NGE-SEED-NAVSCHEMA',
  String? scheme = 'URN',
}) =>
    EpubNavigationHeadMeta(name: name, content: content, scheme: scheme);

EpubNavigationHead seedHead({List<EpubNavigationHeadMeta>? metadata}) =>
    EpubNavigationHead(
      metadata: metadata ?? <EpubNavigationHeadMeta>[seedHeadMeta()],
    );

EpubNavigationDocTitle seedDocTitle({List<String>? titles}) =>
    EpubNavigationDocTitle(
      titles: titles ?? <String>['NGE-SEED Navigation Book'],
    );

EpubNavigationDocAuthor seedDocAuthor({List<String>? authors}) =>
    EpubNavigationDocAuthor(authors: authors ?? <String>['NGE-SEED Author']);

EpubNavigationPoint seedPoint({
  String id = 'np-1',
  String? navClass = 'chapter',
  String playOrder = '1',
  List<EpubNavigationLabel>? labels,
  EpubNavigationContent? content,
  List<EpubNavigationPoint>? children,
}) =>
    EpubNavigationPoint(
      id: id,
      className: navClass,
      playOrder: playOrder,
      navigationLabels: labels ?? <EpubNavigationLabel>[seedLabel()],
      content: content ?? seedNavContent(),
      childNavigationPoints: children ?? <EpubNavigationPoint>[],
    );

EpubNavigationMap seedMap({List<EpubNavigationPoint>? points}) =>
    EpubNavigationMap(points: points ?? <EpubNavigationPoint>[seedPoint()]);

EpubNavigationPageTarget seedPageTarget({
  String id = 'pt-1',
  String? value = '1',
  EpubNavigationPageTargetType type = EpubNavigationPageTargetType.normal,
  String? targetClass = 'pagenum',
  String playOrder = '1',
  List<EpubNavigationLabel>? labels,
  EpubNavigationContent? content,
}) =>
    EpubNavigationPageTarget(
      id: id,
      value: value,
      type: type,
      className: targetClass,
      playOrder: playOrder,
      navigationLabels: labels ?? <EpubNavigationLabel>[seedLabel()],
      content: content ?? seedNavContent(),
    );

EpubNavigationPageList seedPageList({
  List<EpubNavigationPageTarget>? targets,
}) =>
    EpubNavigationPageList(
      targets: targets ?? <EpubNavigationPageTarget>[seedPageTarget()],
    );

EpubNavigationTarget seedTarget({
  String id = 'nt-1',
  String? targetClass = 'illustration',
  String? value = 'NGE-SEED Figure 1',
  String playOrder = '1',
  List<EpubNavigationLabel>? labels,
  EpubNavigationContent? content,
}) =>
    EpubNavigationTarget(
      id: id,
      className: targetClass,
      value: value,
      playOrder: playOrder,
      navigationLabels: labels ?? <EpubNavigationLabel>[seedLabel()],
      content: content ?? seedNavContent(),
    );

EpubNavigationList seedList({
  String? id = 'nl-1',
  String? listClass = 'illustrations',
  List<EpubNavigationLabel>? labels,
  List<EpubNavigationTarget>? targets,
}) =>
    EpubNavigationList(
      id: id,
      className: listClass,
      navigationLabels: labels ?? <EpubNavigationLabel>[seedLabel()],
      navigationTargets: targets ?? <EpubNavigationTarget>[seedTarget()],
    );

/// A navigation with every field populated. `pageList` defaults to
/// [seedPageList] only when the caller passes nothing; [withoutPageList]
/// builds the page-list-less variant, since an explicit null cannot be told
/// apart from "not passed" here.
EpubNavigation seedNavigation({
  EpubNavigationHead? head,
  EpubNavigationDocTitle? docTitle,
  List<EpubNavigationDocAuthor>? docAuthors,
  EpubNavigationMap? navMap,
  EpubNavigationPageList? pageList,
  bool withoutPageList = false,
  List<EpubNavigationList>? navLists,
}) =>
    EpubNavigation(
      head: head ?? seedHead(),
      docTitle: docTitle ?? seedDocTitle(),
      docAuthors: docAuthors ?? <EpubNavigationDocAuthor>[seedDocAuthor()],
      navMap: navMap ?? seedMap(),
      pageList: withoutPageList ? null : pageList ?? seedPageList(),
      navLists: navLists ?? <EpubNavigationList>[seedList()],
    );

/// An operand of an unrelated type, held as `Object` so each comparison below
/// is a real runtime check. Typing it `Object` rather than inlining a literal
/// is what keeps these tests free of an `unrelated_type_equality_checks`
/// suppression, which this package's lint forbids outright.
const Object unrelatedOperand = 'NGE-SEED-not-a-domain-object';

/// A null operand, typed nullable so the analyzer does not fold the comparison
/// away as a statically-known mismatch. Every class under test must answer
/// false here rather than throw.
const Object? nullOperand = null;

/// Asserts that [a] and [b] differ on both `==` and `hashCode`: a partition
/// row that checked only `==` would let a field silently drop out of the hash.
void expectDistinct(Object a, Object b) {
  expect(a, isNot(equals(b)));
  expect(a.hashCode, isNot(equals(b.hashCode)));
}

void main() {
  group('The navigation layer as a whole', () {
    // TC-NSC-1 [Error guessing]: every `==` in this directory opens with an
    // `is` check, so an unrelated operand and a null one both answer false
    // rather than throw a `TypeError` — the Dart equality contract.
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

    // TC-NSC-3 [Boundary value]: an EPUB 3 nav heading (`<span>`, or `<a>`
    // with no `href`) reads as a point with an empty id and playOrder and a
    // content with no source. `toString` reads `content.source`, so it must
    // print that absent source as `null` rather than throw, and the point
    // still hashes.
    test(
        'TC-NSC-3 [Boundary]: a heading-only point with no content source '
        'hashes and prints', () {
      final EpubNavigationPoint heading = seedPoint(
        id: '',
        playOrder: '',
        content: const EpubNavigationContent(),
      );

      expect(heading.hashCode, isA<int>());
      expect(heading.toString(), 'Id: , Content.Source: null');
      expectDistinct(heading, seedPoint(id: '', playOrder: ''));
    });

    // TC-NSC-4 [Boundary value]: a label's `toString` is its text verbatim, so
    // a label whose `<text>` is empty prints as the empty string.
    test('TC-NSC-4 [Boundary]: a label prints as its text, empty included', () {
      expect(seedLabel('').toString(), isEmpty);
      expect(seedLabel().toString(), 'NGE-SEED Label');
    });

    // TC-NSC-6 [Boundary value]: a bare `<navList/>` reads as a list with no
    // id, no class, and empty label and target lists. That sparsest shape
    // hashes, compares, and differs from a populated navList.
    test('TC-NSC-6 [Boundary]: a bare EpubNavigationList hashes and compares',
        () {
      EpubNavigationList bare() => seedList(
            id: null,
            listClass: null,
            labels: <EpubNavigationLabel>[],
            targets: <EpubNavigationTarget>[],
          );

      expect(bare().hashCode, equals(bare().hashCode));
      expect(bare(), equals(bare()));
      expectDistinct(bare(), seedList());
    });

    // TC-NSC-7 [Scenario/use-case]: every class agrees with its own twin. The
    // twins are built separately, so neither comparison can pass on identity
    // alone.
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
        expect(identical(row.value[0], row.value[1]), isFalse);
        expect(row.value[0], equals(row.value[1]));
        expect(row.value[0].hashCode, equals(row.value[1].hashCode));
      });
    }

    // TC-NSC-32 [Boundary value]: each field the NCX makes optional is
    // nullable, and a null there is a distinct value — it equals another
    // null and differs from the populated field on `==` and `hashCode`.
    for (final MapEntry<String, List<Object>> row in <String, List<Object>>{
      'EpubNavigation.pageList': <Object>[
        seedNavigation(withoutPageList: true),
        seedNavigation(withoutPageList: true),
        seedNavigation(),
      ],
      'EpubNavigationContent.id': <Object>[
        seedNavContent(id: null),
        seedNavContent(id: null),
        seedNavContent(),
      ],
      'EpubNavigationContent.source': <Object>[
        seedNavContent(source: null),
        seedNavContent(source: null),
        seedNavContent(),
      ],
      'EpubNavigationHeadMeta.scheme': <Object>[
        seedHeadMeta(scheme: null),
        seedHeadMeta(scheme: null),
        seedHeadMeta(),
      ],
      'EpubNavigationPoint.className': <Object>[
        seedPoint(navClass: null),
        seedPoint(navClass: null),
        seedPoint(),
      ],
      'EpubNavigationPageTarget.value': <Object>[
        seedPageTarget(value: null),
        seedPageTarget(value: null),
        seedPageTarget(),
      ],
      'EpubNavigationPageTarget.className': <Object>[
        seedPageTarget(targetClass: null),
        seedPageTarget(targetClass: null),
        seedPageTarget(),
      ],
      'EpubNavigationTarget.className': <Object>[
        seedTarget(targetClass: null),
        seedTarget(targetClass: null),
        seedTarget(),
      ],
      'EpubNavigationTarget.value': <Object>[
        seedTarget(value: null),
        seedTarget(value: null),
        seedTarget(),
      ],
      'EpubNavigationList.id': <Object>[
        seedList(id: null),
        seedList(id: null),
        seedList(),
      ],
      'EpubNavigationList.className': <Object>[
        seedList(listClass: null),
        seedList(listClass: null),
        seedList(),
      ],
    }.entries) {
      test(
          'TC-NSC-32 [Boundary]: a null ${row.key} equals another null and '
          'differs from a value', () {
        expect(row.value[0], equals(row.value[1]));
        expect(row.value[0].hashCode, equals(row.value[1].hashCode));
        expectDistinct(row.value[0], row.value[2]);
      });
    }
  });

  group('EpubNavigationLabel / EpubNavigationContent', () {
    // TC-NSC-8 [Equivalence partitioning]: a label is its text.
    test('TC-NSC-8 [Equivalence partitioning]: labels differ by text', () {
      expectDistinct(seedLabel(), seedLabel('NGE-SEED Other'));
      expect(seedLabel(''), equals(seedLabel('')));
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
        expectDistinct(seedNavContent(), row.value);
      });
    }

    // TC-NSC-10 [Scenario/use-case]: content renders its source only — the id
    // is deliberately absent from `toString` — and an absent source as `null`.
    test('TC-NSC-10 [Scenario]: content renders its source', () {
      expect(seedNavContent().toString(), 'Source: chapter1.xhtml');
      expect(const EpubNavigationContent().toString(), 'Source: null');
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
        expectDistinct(seedHeadMeta(), row.value);
      });
    }

    // TC-NSC-12 [Boundary value]: an empty head is what an EPUB 3 nav
    // document reads as, having no NCX head; it hashes and differs from a
    // populated one.
    test('TC-NSC-12 [Boundary]: an empty head hashes and differs', () {
      final EpubNavigationHead empty =
          seedHead(metadata: <EpubNavigationHeadMeta>[]);

      expect(empty.metadata, isEmpty);
      expect(empty, equals(seedHead(metadata: <EpubNavigationHeadMeta>[])));
      expectDistinct(empty, seedHead());
    });

    // TC-NSC-13 [Equivalence partitioning]: the head compares its metadata
    // element-wise, so both count and content decide.
    test('TC-NSC-13 [Equivalence partitioning]: heads differ by metadata list',
        () {
      expectDistinct(
        seedHead(),
        seedHead(
          metadata: <EpubNavigationHeadMeta>[
            seedHeadMeta(),
            seedHeadMeta(name: 'dtb:depth'),
          ],
        ),
      );
      expectDistinct(
        seedHead(),
        seedHead(
          metadata: <EpubNavigationHeadMeta>[seedHeadMeta(name: 'dtb:depth')],
        ),
      );
    });
  });

  group('EpubNavigationDocTitle / EpubNavigationDocAuthor', () {
    // TC-NSC-14 [Equivalence partitioning]: both are thin list wrappers, so
    // an empty list and a differing entry each decide.
    test('TC-NSC-14 [Equivalence partitioning]: doc titles differ by titles',
        () {
      expectDistinct(seedDocTitle(), seedDocTitle(titles: <String>[]));
      expectDistinct(
        seedDocTitle(),
        seedDocTitle(titles: <String>['NGE-SEED Other']),
      );
    });

    test('TC-NSC-14 [Equivalence partitioning]: doc authors differ by authors',
        () {
      expectDistinct(seedDocAuthor(), seedDocAuthor(authors: <String>[]));
      expectDistinct(
        seedDocAuthor(),
        seedDocAuthor(authors: <String>['NGE-SEED Other']),
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
        expectDistinct(seedPoint(), row.value);
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
      expectDistinct(tree('np-1-1-1'), tree('np-1-1-2'));
    });

    // TC-NSC-19 [Boundary value]: a map with no point is what the reader
    // produces for an empty `<navMap>`; it hashes, compares, and differs from
    // a populated map, and the map compares its points element-wise.
    test('TC-NSC-19 [Boundary]: an empty map hashes and compares', () {
      final EpubNavigationMap empty = seedMap(points: <EpubNavigationPoint>[]);

      expect(empty, equals(seedMap(points: <EpubNavigationPoint>[])));
      expectDistinct(empty, seedMap());
      expectDistinct(
        seedMap(),
        seedMap(points: <EpubNavigationPoint>[seedPoint(id: 'np-2')]),
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
        expectDistinct(seedPageTarget(), row.value);
      });
    }

    // TC-NSC-21 [Boundary value]: all four enum values are distinct operands,
    // and `undefined` is the reader's fallback for an absent or unrecognised
    // `type`.
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
    });

    // TC-NSC-22 [Boundary value]: a page list with no target is what the
    // reader produces for an empty `<pageList>`; it hashes, compares, and the
    // list compares its targets element-wise.
    test('TC-NSC-22 [Boundary]: an empty page list hashes and differs', () {
      final EpubNavigationPageList empty =
          seedPageList(targets: <EpubNavigationPageTarget>[]);

      expect(
        empty,
        equals(seedPageList(targets: <EpubNavigationPageTarget>[])),
      );
      expectDistinct(empty, seedPageList());
      expectDistinct(
        seedPageList(),
        seedPageList(
          targets: <EpubNavigationPageTarget>[seedPageTarget(id: 'pt-2')],
        ),
      );
    });

    // TC-NSC-33 [Boundary value]: a `<pageTarget>` with no `<content>` reads
    // with a content carrying neither id nor source. That target hashes and
    // differs from one pointing somewhere.
    test(
        'TC-NSC-33 [Boundary]: a page target whose content has no source '
        'hashes and differs', () {
      final EpubNavigationPageTarget noContent =
          seedPageTarget(content: const EpubNavigationContent());

      expect(noContent.content.source, isNull);
      expect(noContent.hashCode, isA<int>());
      expectDistinct(noContent, seedPageTarget());
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
        expectDistinct(seedTarget(), row.value);
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
        expectDistinct(seedList(), row.value);
      });
    }
  });

  group('EpubNavigation', () {
    // TC-NSC-26 [Equivalence partitioning]: all six fields decide. `docAuthors`
    // and `navLists` are checked before the four scalars, so each gets a row.
    for (final MapEntry<String, EpubNavigation> row in <String, EpubNavigation>{
      'head': seedNavigation(
        head: seedHead(
          metadata: <EpubNavigationHeadMeta>[seedHeadMeta(name: 'dtb:depth')],
        ),
      ),
      'docTitle': seedNavigation(
        docTitle: seedDocTitle(titles: <String>['NGE-SEED Other']),
      ),
      'docAuthors': seedNavigation(
        docAuthors: <EpubNavigationDocAuthor>[
          seedDocAuthor(authors: <String>['NGE-SEED Other']),
        ],
      ),
      'navMap': seedNavigation(
        navMap: seedMap(points: <EpubNavigationPoint>[seedPoint(id: 'np-2')]),
      ),
      'pageList': seedNavigation(
        pageList: seedPageList(
          targets: <EpubNavigationPageTarget>[seedPageTarget(id: 'pt-2')],
        ),
      ),
      'navLists': seedNavigation(
        navLists: <EpubNavigationList>[seedList(id: 'nl-2')],
      ),
    }.entries) {
      test(
          'TC-NSC-26 [Equivalence partitioning]: a navigation with a '
          'differing ${row.key} is unequal', () {
        expectDistinct(seedNavigation(), row.value);
      });
    }

    // TC-NSC-27 [Boundary value]: the sparsest navigation is the EPUB 3 shape
    // — empty head, no doc author, no nav list, no page list. Built from the
    // required arguments alone, its optional fields default to exactly that,
    // and it hashes, compares, and differs from a populated navigation.
    test('TC-NSC-27 [Boundary]: a required-only navigation hashes and compares',
        () {
      EpubNavigation sparse() => EpubNavigation(
            head: seedHead(metadata: <EpubNavigationHeadMeta>[]),
            docTitle: seedDocTitle(titles: <String>[]),
            navMap: seedMap(points: <EpubNavigationPoint>[]),
          );

      expect(sparse().docAuthors, isEmpty);
      expect(sparse().navLists, isEmpty);
      expect(sparse().pageList, isNull);
      expect(sparse(), equals(sparse()));
      expect(sparse().hashCode, equals(sparse().hashCode));
      expectDistinct(sparse(), seedNavigation());
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

      final EpubNavigation a = first.schema.navigation;
      final EpubNavigation b = second.schema.navigation;

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.head, equals(b.head));
      expect(a.docTitle, equals(b.docTitle));
      expect(a.docAuthors, equals(b.docAuthors));
      expect(a.navMap, equals(b.navMap));
      expect(a.pageList, equals(b.pageList));

      // The graph really is populated, so the equality above is not vacuous.
      expect(a.docTitle.titles, <String>['NGE-SEED Navigation Book']);
      expect(a.navMap.points, hasLength(1));
      expect(a.navMap.points.single.childNavigationPoints, hasLength(1));
      expect(a.pageList!.targets, hasLength(1));
      expect(
        a.pageList!.targets.single.type,
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

      final EpubNavigation a = first.schema.navigation;
      final EpubNavigation b = second.schema.navigation;

      expect(a, isNot(equals(b)));
      expect(a.navMap, isNot(equals(b.navMap)));
      expect(a.docTitle, equals(b.docTitle));
      expect(
        a.navMap.points.single.childNavigationPoints.single.navigationLabels
            .single.text,
        'NGE-SEED S1',
      );
    });
  });
}
