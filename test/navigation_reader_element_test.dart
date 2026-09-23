// Element-level behaviour of `NavigationReader`'s public readers, driven
// straight from XML fragments — the style of `spine_direction_test.dart`.
//
// The archive-level guards live in
// `navigation_reader_archive_errors_test.dart`; this file covers what each
// reader does with one node, including the guards that a whole-book fixture
// cannot reach without also tripping an earlier one.
//
// Every test asserts every field the reader under test sets, not only the one
// the scenario is about: a fallback (`''`, an empty list, a sourceless
// content) is a value the reader chooses, and an assertion that skips it
// lets any other value through.
import 'package:novel_glide_epub/src/readers/navigation_reader.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_content.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_doc_author.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_doc_title.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_head.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_head_meta.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_label.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_list.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_map.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_list.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_target.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_target_type.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_point.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_target.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

XmlElement _element(String xml) => XmlDocument.parse(xml).rootElement;

Matcher _throwsMessageContaining(String fragment) => throwsA(
      isA<Exception>().having(
        (Exception e) => e.toString(),
        'message',
        contains(fragment),
      ),
    );

List<String> _labelTexts(List<EpubNavigationLabel> labels) =>
    labels.map((EpubNavigationLabel label) => label.text).toList();

/// A `<navLabel>` with no `<text>`, and a `<content>` with no `src`: the two
/// malformed children the ordering tests put side by side.
const String _malformedLabel = '<navLabel><notText>x</notText></navLabel>';
const String _malformedContent = '<content id="c-bad"/>';
const String _labelMissing = 'label text element is missing';
const String _sourceMissing = 'content source is missing';

/// One row of the `readNavigationContentV3` table: an `<a>` or `<span>`
/// [node] read under [navBase], and the [source] it should resolve to.
class _ContentV3Case {
  const _ContentV3Case({
    required this.node,
    required this.navBase,
    this.source,
  });

  final String node;
  final String navBase;
  final String? source;
}

void main() {
  group('NavigationReader.readNavigationContent', () {
    // TC-NAVU-1 [Scenario/use-case]: an NCX `content` node yields id + src.
    test('TC-NAVU-1 [Scenario]: reads id and src from a content node', () {
      final EpubNavigationContent content = const NavigationReader()
          .readNavigationContent(
              _element('<content id="c-1" src="chapter1.xhtml#a"/>'));

      expect(content.id, 'c-1');
      expect(content.source, 'chapter1.xhtml#a');
    });

    // TC-NAVU-2 [Boundary value]: src absent and src empty are both rejected
    // — the two sides of the `source == null || source.isEmpty` guard.
    for (final String node in <String>[
      '<content id="c-1"/>',
      '<content id="c-1" src=""/>',
    ]) {
      test(
          'TC-NAVU-2 [Boundary]: content without a usable src is rejected '
          '($node)', () {
        expect(
          () => const NavigationReader().readNavigationContent(_element(node)),
          _throwsMessageContaining(_sourceMissing),
        );
      });
    }

    // TC-NAVU-30 [Equivalence partitioning]: `id` is optional on an NCX
    // content, so its absence reads as null rather than refusing the entry.
    test(
        'TC-NAVU-30 [Equivalence partitioning]: content without an id reads '
        'id null', () {
      final EpubNavigationContent content = const NavigationReader()
          .readNavigationContent(_element('<content src="chapter1.xhtml"/>'));

      expect(content.id, isNull);
      expect(content.source, 'chapter1.xhtml');
    });
  });

  group('NavigationReader.readNavigationHead', () {
    // TC-NAVU-3 [Scenario/use-case]: meta name/content/scheme are read, in
    // document order, and non-meta children ignored.
    test(
        'TC-NAVU-3 [Scenario]: reads meta attributes and skips non-meta '
        'children', () {
      final EpubNavigationHead head =
          const NavigationReader().readNavigationHead(
        _element('<head>'
            '<meta name="dtb:uid" content="NGE-SEED-UID" scheme="uuid"/>'
            '<notMeta name="ignored"/>'
            '<meta name="dtb:depth" content="2"/>'
            '</head>'),
      );

      expect(head.metadata, hasLength(2));
      final EpubNavigationHeadMeta uid = head.metadata[0];
      expect(uid.name, 'dtb:uid');
      expect(uid.content, 'NGE-SEED-UID');
      expect(uid.scheme, 'uuid');
      final EpubNavigationHeadMeta depth = head.metadata[1];
      expect(depth.name, 'dtb:depth');
      expect(depth.content, '2');
      expect(depth.scheme, isNull);
    });

    // TC-NAVU-4 [Error guessing]: a meta must carry a non-empty name and a
    // content attribute (empty content is allowed, absent is not).
    test('TC-NAVU-4 [Error guessing]: meta without a name is rejected', () {
      expect(
        () => const NavigationReader().readNavigationHead(
          _element('<head><meta content="NGE-SEED-UID"/></head>'),
        ),
        _throwsMessageContaining('meta name is missing'),
      );
    });

    test('TC-NAVU-5 [Error guessing]: meta without content is rejected', () {
      expect(
        () => const NavigationReader().readNavigationHead(
          _element('<head><meta name="dtb:uid"/></head>'),
        ),
        _throwsMessageContaining('meta content is missing'),
      );
    });

    // TC-NAVU-6 [Boundary value]: content="" passes the guard — the guard is
    // null-only, unlike the name guard beside it.
    test('TC-NAVU-6 [Boundary]: meta with empty content is accepted', () {
      final EpubNavigationHead head =
          const NavigationReader().readNavigationHead(
        _element('<head><meta name="dtb:depth" content=""/></head>'),
      );

      expect(head.metadata.single.name, 'dtb:depth');
      expect(head.metadata.single.content, isEmpty);
      expect(head.metadata.single.scheme, isNull);
    });

    // TC-NAVU-31 [Boundary value]: name="" is rejected like an absent name —
    // the other side of the name guard from TC-NAVU-4.
    test('TC-NAVU-31 [Boundary]: meta with an empty name is rejected', () {
      expect(
        () => const NavigationReader().readNavigationHead(
          _element('<head><meta name="" content="NGE-SEED-UID"/></head>'),
        ),
        _throwsMessageContaining('meta name is missing'),
      );
    });

    // TC-NAVU-32 [Boundary value]: a head with no meta reads an empty list;
    // NCX requires one, but nothing downstream needs it.
    test('TC-NAVU-32 [Boundary]: a head with no meta reads empty metadata', () {
      final EpubNavigationHead head =
          const NavigationReader().readNavigationHead(_element('<head/>'));

      expect(head.metadata, isEmpty);
    });
  });

  group('NavigationReader doc title / doc author', () {
    // TC-NAVU-7 [Scenario/use-case]: repeated text children accumulate and
    // foreign children are skipped, for both readers.
    test('TC-NAVU-7 [Scenario]: docTitle collects text children only', () {
      final EpubNavigationDocTitle title =
          const NavigationReader().readNavigationDocTitle(
        _element('<docTitle><text>NGE-SEED A</text><img src="x"/>'
            '<text>NGE-SEED B</text></docTitle>'),
      );

      expect(title.titles, <String>['NGE-SEED A', 'NGE-SEED B']);
    });

    test('TC-NAVU-8 [Scenario]: docAuthor collects text children only', () {
      final EpubNavigationDocAuthor author =
          const NavigationReader().readNavigationDocAuthor(
        _element('<docAuthor><img src="x"/><text>NGE-SEED Author</text>'
            '</docAuthor>'),
      );

      expect(author.authors, <String>['NGE-SEED Author']);
    });

    // TC-NAVU-33 [Boundary value]: with no text child, both read an empty
    // list rather than refusing the book.
    test(
        'TC-NAVU-33 [Boundary]: docTitle and docAuthor with no text read '
        'empty', () {
      expect(
        const NavigationReader()
            .readNavigationDocTitle(_element('<docTitle/>'))
            .titles,
        isEmpty,
      );
      expect(
        const NavigationReader()
            .readNavigationDocAuthor(_element('<docAuthor/>'))
            .authors,
        isEmpty,
      );
    });
  });

  group('NavigationReader.readNavigationLabel', () {
    // TC-NAVU-9 [Scenario/use-case]: the label's text element supplies text.
    test('TC-NAVU-9 [Scenario]: reads the label text element', () {
      final EpubNavigationLabel label =
          const NavigationReader().readNavigationLabel(
        _element('<navLabel><text>NGE-SEED Label</text></navLabel>'),
      );

      expect(label.text, 'NGE-SEED Label');
    });

    // TC-NAVU-10 [Error guessing]: a label with no text element is rejected.
    test(
        'TC-NAVU-10 [Error guessing]: label without a text element is '
        'rejected', () {
      expect(
        () => const NavigationReader().readNavigationLabel(
          _element('<navLabel><notText>x</notText></navLabel>'),
        ),
        _throwsMessageContaining(_labelMissing),
      );
    });

    // TC-NAVU-11 [Scenario/use-case]: the EPUB3 label reader takes the node's
    // own text, trimmed — there is no nested text element in a nav document.
    test('TC-NAVU-11 [Scenario]: the V3 label reader trims the node text', () {
      final EpubNavigationLabel label =
          const NavigationReader().readNavigationLabelV3(
        _element('<a href="chapter1.xhtml">  NGE-SEED V3 Label  </a>'),
      );

      expect(label.text, 'NGE-SEED V3 Label');
    });

    // TC-NAVU-34 [Equivalence partitioning]: of several text elements the
    // first is the label's; the rest are not concatenated in.
    test(
        'TC-NAVU-34 [Equivalence partitioning]: the first text element is '
        'the label', () {
      final EpubNavigationLabel label =
          const NavigationReader().readNavigationLabel(
        _element('<navLabel><text>NGE-SEED First</text>'
            '<text>NGE-SEED Second</text></navLabel>'),
      );

      expect(label.text, 'NGE-SEED First');
    });

    // TC-NAVU-35 [Error guessing]: the text element must share the label's
    // namespace. A `text` from a foreign vocabulary is not the NCX one, so a
    // label carrying only that has no text.
    test(
        'TC-NAVU-35 [Error guessing]: a text element in a foreign namespace '
        'is not the label text', () {
      expect(
        () => const NavigationReader().readNavigationLabel(
          _element('<navLabel xmlns="http://www.daisy.org/z3986/2005/ncx/">'
              '<x:text xmlns:x="urn:nge-seed">NGE-SEED Foreign</x:text>'
              '</navLabel>'),
        ),
        _throwsMessageContaining(_labelMissing),
      );
    });
  });

  group('NavigationReader.readNavigationPoint', () {
    const String label = '<navLabel><text>NGE-SEED Point</text></navLabel>';
    const String content = '<content src="chapter1.xhtml"/>';

    // TC-NAVU-12 [Error guessing]: id, at least one label, and content are
    // each required, and each has its own message.
    test('TC-NAVU-12 [Error guessing]: navPoint without an id is rejected', () {
      expect(
        () => const NavigationReader().readNavigationPoint(
          _element('<navPoint>$label$content</navPoint>'),
        ),
        _throwsMessageContaining('point ID is missing'),
      );
    });

    test(
        'TC-NAVU-13 [Error guessing]: navPoint without a navLabel is '
        'rejected', () {
      expect(
        () => const NavigationReader().readNavigationPoint(
          _element('<navPoint id="np-1">$content</navPoint>'),
        ),
        _throwsMessageContaining(
            'navigation point np-1 should contain at least one navigation '
            'label'),
      );
    });

    test('TC-NAVU-14 [Error guessing]: navPoint without content is rejected',
        () {
      expect(
        () => const NavigationReader().readNavigationPoint(
          _element('<navPoint id="np-1">$label</navPoint>'),
        ),
        _throwsMessageContaining(
            'navigation point np-1 should contain content'),
      );
    });

    // TC-NAVU-15 [Boundary value]: an empty id is rejected like an absent one.
    test('TC-NAVU-15 [Boundary]: navPoint with an empty id is rejected', () {
      expect(
        () => const NavigationReader().readNavigationPoint(
          _element('<navPoint id="">$label$content</navPoint>'),
        ),
        _throwsMessageContaining('point ID is missing'),
      );
    });

    // TC-NAVU-36 [Scenario/use-case]: every attribute and child is read —
    // labels accumulate in order, and a nested navPoint becomes a child.
    test(
        'TC-NAVU-36 [Scenario]: reads every attribute and child of a '
        'navPoint', () {
      final EpubNavigationPoint point =
          const NavigationReader().readNavigationPoint(
        _element('<navPoint id="np-1" class="chapter" playOrder="7">'
            '<navLabel><text>NGE-SEED One</text></navLabel>'
            '<navLabel><text>NGE-SEED Uno</text></navLabel>'
            '<content id="c-1" src="chapter1.xhtml"/>'
            '<navPoint id="np-1-1" playOrder="8">'
            '<navLabel><text>NGE-SEED One.One</text></navLabel>'
            '<content src="chapter1.xhtml#s1"/>'
            '</navPoint>'
            '</navPoint>'),
      );

      expect(point.id, 'np-1');
      expect(point.className, 'chapter');
      expect(point.playOrder, '7');
      expect(_labelTexts(point.navigationLabels),
          <String>['NGE-SEED One', 'NGE-SEED Uno']);
      expect(point.content.id, 'c-1');
      expect(point.content.source, 'chapter1.xhtml');

      final EpubNavigationPoint child = point.childNavigationPoints.single;
      expect(child.id, 'np-1-1');
      expect(child.className, isNull);
      expect(child.playOrder, '8');
      expect(_labelTexts(child.navigationLabels), <String>['NGE-SEED One.One']);
      expect(child.content.id, isNull);
      expect(child.content.source, 'chapter1.xhtml#s1');
      expect(child.childNavigationPoints, isEmpty);
    });

    // TC-NAVU-37 [Boundary value]: `class` is optional and `playOrder`, which
    // NCX requires, reads '' when absent rather than refusing the point.
    test(
        'TC-NAVU-37 [Boundary]: navPoint without class or playOrder reads '
        'null and empty', () {
      final EpubNavigationPoint point = const NavigationReader()
          .readNavigationPoint(_element('<navPoint id="np-1">$label$content'
              '</navPoint>'));

      expect(point.id, 'np-1');
      expect(point.className, isNull);
      expect(point.playOrder, '');
      expect(_labelTexts(point.navigationLabels), <String>['NGE-SEED Point']);
      expect(point.content.source, 'chapter1.xhtml');
      expect(point.childNavigationPoints, isEmpty);
    });

    // TC-NAVU-38 [Equivalence partitioning]: of several `<content>` children
    // the last is the point's.
    test(
        'TC-NAVU-38 [Equivalence partitioning]: the last content child is '
        'the point content', () {
      final EpubNavigationPoint point =
          const NavigationReader().readNavigationPoint(
        _element('<navPoint id="np-1">$label'
            '<content id="c-first" src="first.xhtml"/>'
            '<content id="c-last" src="last.xhtml"/>'
            '</navPoint>'),
      );

      expect(point.content.id, 'c-last');
      expect(point.content.source, 'last.xhtml');
    });

    // TC-NAVU-39 [Error guessing]: the children are read in document order,
    // so of two malformed children the first is the one reported — whichever
    // kind it is.
    for (final MapEntry<String, String> order in <String, String>{
      '$_malformedLabel$_malformedContent': _labelMissing,
      '$_malformedContent$_malformedLabel': _sourceMissing,
      '<navPoint id="np-1-1">$_malformedContent</navPoint>$_malformedLabel':
          _sourceMissing,
    }.entries) {
      test(
        'TC-NAVU-39 [Error guessing]: the first malformed navPoint child is '
        'reported (${order.value})',
        () {
          expect(
            () => const NavigationReader().readNavigationPoint(
              _element('<navPoint id="np-1">${order.key}</navPoint>'),
            ),
            _throwsMessageContaining(order.value),
          );
        },
      );
    }

    // TC-NAVU-40 [Error guessing]: the id guard runs before any child is
    // read, so an id-less point with a malformed child reports the id.
    test(
        'TC-NAVU-40 [Error guessing]: the missing id is reported before a '
        'malformed child', () {
      expect(
        () => const NavigationReader().readNavigationPoint(
          _element('<navPoint>$_malformedLabel</navPoint>'),
        ),
        _throwsMessageContaining('point ID is missing'),
      );
    });

    // TC-NAVU-41 [Error guessing]: with neither label nor content, the label
    // is the one reported — the label check runs first.
    test(
        'TC-NAVU-41 [Error guessing]: a childless navPoint reports the '
        'missing label first', () {
      expect(
        () => const NavigationReader()
            .readNavigationPoint(_element('<navPoint id="np-1"/>')),
        _throwsMessageContaining('at least one navigation label'),
      );
    });
  });

  group('NavigationReader.readNavigationPointV3', () {
    // TC-NAVU-42 [Scenario/use-case]: an EPUB3 entry has no NCX id, class or
    // play order, so id and playOrder read '' and className null; the `<a>`
    // is both label and content, and a nested `<ol>` holds the children.
    test(
        'TC-NAVU-42 [Scenario]: an li reads empty id and playOrder, its '
        'anchor, and its nested ol', () {
      final EpubNavigationPoint point =
          const NavigationReader().readNavigationPointV3(
        _element('<li id="li-1" class="nge-seed">'
            '<a id="a-1" href="chapter1.xhtml"> NGE-SEED One </a>'
            '<ol><li><a href="chapter1.xhtml#s1">NGE-SEED One.One</a></li>'
            '<li><span>NGE-SEED Heading</span></li></ol>'
            '</li>'),
        'OEBPS/',
      );

      expect(point.id, '');
      expect(point.className, isNull);
      expect(point.playOrder, '');
      expect(_labelTexts(point.navigationLabels), <String>['NGE-SEED One']);
      expect(point.content.id, 'a-1');
      expect(point.content.source, 'OEBPS/chapter1.xhtml');
      expect(point.childNavigationPoints, hasLength(2));
      expect(point.childNavigationPoints[0].id, '');
      expect(point.childNavigationPoints[0].playOrder, '');
      expect(point.childNavigationPoints[0].content.source,
          'OEBPS/chapter1.xhtml#s1');
      expect(point.childNavigationPoints[1].content.source, isNull);
      expect(_labelTexts(point.childNavigationPoints[1].navigationLabels),
          <String>['NGE-SEED Heading']);
    });

    // TC-NAVU-43 [Equivalence partitioning]: an li with both an `<a>` and a
    // `<span>` keeps both labels and takes the content of the last.
    test(
        'TC-NAVU-43 [Equivalence partitioning]: the last anchor or span '
        'supplies the content', () {
      final EpubNavigationPoint point =
          const NavigationReader().readNavigationPointV3(
        _element('<li><a href="chapter1.xhtml">NGE-SEED A</a>'
            '<span id="s-1">NGE-SEED Span</span></li>'),
        '',
      );

      expect(_labelTexts(point.navigationLabels),
          <String>['NGE-SEED A', 'NGE-SEED Span']);
      expect(point.content.id, 's-1');
      expect(point.content.source, isNull);
    });
  });

  group('NavigationReader.readNavigationMap', () {
    // TC-NAVU-16 [Scenario/use-case]: only `navPoint` children are walked.
    test('TC-NAVU-16 [Scenario]: navMap skips non-navPoint children', () {
      final EpubNavigationMap map = const NavigationReader().readNavigationMap(
        _element('<navMap>'
            '<pageTarget id="ignored"/>'
            '<navPoint id="np-1">'
            '<navLabel><text>NGE-SEED Point</text></navLabel>'
            '<content src="chapter1.xhtml"/>'
            '</navPoint>'
            '</navMap>'),
      );

      expect(map.points, hasLength(1));
      expect(map.points.single.id, 'np-1');
    });

    // TC-NAVU-44 [Equivalence partitioning]: the navPoint match ignores case,
    // unlike the pageTarget match TC-NAVU-21 pins.
    test(
        'TC-NAVU-44 [Equivalence partitioning]: navMap matches navPoint in '
        'any case', () {
      final EpubNavigationMap map = const NavigationReader().readNavigationMap(
        _element('<navMap>'
            '<NAVPOINT id="np-1">'
            '<navLabel><text>NGE-SEED Point</text></navLabel>'
            '<content src="chapter1.xhtml"/>'
            '</NAVPOINT>'
            '</navMap>'),
      );

      expect(map.points.single.id, 'np-1');
    });

    // TC-NAVU-45 [Boundary value]: an empty navMap reads no points.
    test('TC-NAVU-45 [Boundary]: an empty navMap reads no points', () {
      expect(
        const NavigationReader()
            .readNavigationMap(_element('<navMap/>'))
            .points,
        isEmpty,
      );
    });
  });

  group('NavigationReader.readNavigationPageTarget', () {
    const String label = '<navLabel><text>NGE-SEED 1</text></navLabel>';

    // TC-NAVU-17 [Equivalence partitioning]: every declared page-target type
    // string resolves to its enum value.
    for (final MapEntry<String, EpubNavigationPageTargetType> pair
        in <String, EpubNavigationPageTargetType>{
      'front': EpubNavigationPageTargetType.front,
      'normal': EpubNavigationPageTargetType.normal,
      'special': EpubNavigationPageTargetType.special,
    }.entries) {
      test(
        'TC-NAVU-17 [Equivalence partitioning]: page target type '
        '"${pair.key}" resolves to ${pair.value}',
        () {
          final EpubNavigationPageTarget target =
              const NavigationReader().readNavigationPageTarget(
            _element('<pageTarget id="pt-1" value="1" type="${pair.key}" '
                'class="pagenum" playOrder="2">$label'
                '<content id="c-1" src="chapter1.xhtml#p1"/></pageTarget>'),
          );

          expect(target.type, pair.value);
          expect(target.id, 'pt-1');
          expect(target.value, '1');
          expect(target.className, 'pagenum');
          expect(target.playOrder, '2');
          expect(_labelTexts(target.navigationLabels), <String>['NGE-SEED 1']);
          expect(target.content.id, 'c-1');
          expect(target.content.source, 'chapter1.xhtml#p1');
        },
      );
    }

    // TC-NAVU-18 [Error guessing]: `type="undefined"` is the one value the
    // guard rejects: `undefined` is this parser's stand-in for "no NCX type",
    // not a type a book may name. An absent or unrecognised type reads as
    // `undefined` instead (TC-NAVU-19).
    test(
        'TC-NAVU-18 [Error guessing]: page target typed "undefined" is '
        'rejected', () {
      expect(
        () => const NavigationReader().readNavigationPageTarget(
          _element('<pageTarget id="pt-1" type="undefined">$label'
              '</pageTarget>'),
        ),
        _throwsMessageContaining('page target type is missing'),
      );
    });

    // TC-NAVU-19 [Equivalence partitioning]: an absent type and one naming no
    // NCX page type both read as `undefined` rather than refusing the book.
    for (final String typeAttribute in <String>[
      ' type="nge-seed-unknown"',
      '',
    ]) {
      test(
          'TC-NAVU-19 [Equivalence partitioning]: page target with type '
          '"$typeAttribute" reads type undefined', () {
        final EpubNavigationPageTarget target =
            const NavigationReader().readNavigationPageTarget(
          _element('<pageTarget id="pt-1"$typeAttribute>$label'
              '</pageTarget>'),
        );

        expect(target.type, EpubNavigationPageTargetType.undefined);
      });
    }

    // TC-NAVU-20 [Error guessing]: a page target needs at least one navLabel.
    test(
        'TC-NAVU-20 [Error guessing]: page target without a navLabel is '
        'rejected', () {
      expect(
        () => const NavigationReader().readNavigationPageTarget(
          _element('<pageTarget id="pt-1" type="normal">'
              '<content src="chapter1.xhtml"/></pageTarget>'),
        ),
        _throwsMessageContaining(
            'navigation page target: at least one navLabel element is '
            'required'),
      );
    });

    // TC-NAVU-46 [Boundary value]: `id`, `playOrder` and `<content>`, which
    // NCX requires, read '' / '' / a sourceless content when absent; `value`
    // and `class` are optional and read null.
    test(
        'TC-NAVU-46 [Boundary]: a page target with only a label reads its '
        'fallbacks', () {
      final EpubNavigationPageTarget target = const NavigationReader()
          .readNavigationPageTarget(
              _element('<pageTarget type="normal">$label</pageTarget>'));

      expect(target.id, '');
      expect(target.value, isNull);
      expect(target.type, EpubNavigationPageTargetType.normal);
      expect(target.className, isNull);
      expect(target.playOrder, '');
      expect(_labelTexts(target.navigationLabels), <String>['NGE-SEED 1']);
      expect(target.content.id, isNull);
      expect(target.content.source, isNull);
    });

    // TC-NAVU-47 [Equivalence partitioning]: of several `<content>` children
    // the last is the target's.
    test(
        'TC-NAVU-47 [Equivalence partitioning]: the last content child is '
        'the page target content', () {
      final EpubNavigationPageTarget target =
          const NavigationReader().readNavigationPageTarget(
        _element('<pageTarget id="pt-1" type="normal">$label'
            '<content src="first.xhtml"/><content src="last.xhtml"/>'
            '</pageTarget>'),
      );

      expect(target.content.source, 'last.xhtml');
    });

    // TC-NAVU-48 [Error guessing]: the children are read in document order,
    // so of two malformed children the first is the one reported; and a
    // malformed child is reported before the missing-label guard runs.
    for (final MapEntry<String, String> order in <String, String>{
      '$_malformedLabel$_malformedContent': _labelMissing,
      '$_malformedContent$_malformedLabel': _sourceMissing,
      _malformedContent: _sourceMissing,
    }.entries) {
      test(
        'TC-NAVU-48 [Error guessing]: the first malformed page target child '
        'is reported (${order.value})',
        () {
          expect(
            () => const NavigationReader().readNavigationPageTarget(
              _element('<pageTarget id="pt-1" type="normal">${order.key}'
                  '</pageTarget>'),
            ),
            _throwsMessageContaining(order.value),
          );
        },
      );
    }

    // TC-NAVU-49 [Error guessing]: the type guard runs before any child is
    // read.
    test(
        'TC-NAVU-49 [Error guessing]: an "undefined" type is reported '
        'before a malformed child', () {
      expect(
        () => const NavigationReader().readNavigationPageTarget(
          _element('<pageTarget id="pt-1" type="undefined">$_malformedLabel'
              '</pageTarget>'),
        ),
        _throwsMessageContaining('page target type is missing'),
      );
    });
  });

  group('NavigationReader.readNavigationPageList', () {
    // TC-NAVU-21 [Scenario/use-case]: only `pageTarget` children are walked,
    // and the match is case-sensitive unlike its siblings.
    test(
        'TC-NAVU-21 [Scenario]: pageList skips children that are not '
        'pageTarget', () {
      final EpubNavigationPageList list =
          const NavigationReader().readNavigationPageList(
        _element('<pageList>'
            '<PAGETARGET id="wrong-case" type="normal">'
            '<navLabel><text>x</text></navLabel></PAGETARGET>'
            '<pageTarget id="pt-1" type="normal">'
            '<navLabel><text>NGE-SEED 1</text></navLabel>'
            '<content src="chapter1.xhtml"/>'
            '</pageTarget>'
            '</pageList>'),
      );

      expect(list.targets, hasLength(1));
      expect(list.targets.single.id, 'pt-1');
    });
  });

  group('NavigationReader.readNavigationTarget', () {
    const String label = '<navLabel><text>NGE-SEED Target</text></navLabel>';

    // TC-NAVU-22 [Scenario/use-case]: every attribute and child of a
    // navTarget is read.
    test(
        'TC-NAVU-22 [Scenario]: reads every attribute and child of a '
        'navTarget', () {
      final EpubNavigationTarget target =
          const NavigationReader().readNavigationTarget(
        _element('<navTarget id="nt-1" value="v" class="c" playOrder="3">'
            '$label<navLabel><text>NGE-SEED Cible</text></navLabel>'
            '<content id="c-1" src="chapter1.xhtml"/></navTarget>'),
      );

      expect(target.id, 'nt-1');
      expect(target.value, 'v');
      expect(target.className, 'c');
      expect(target.playOrder, '3');
      expect(_labelTexts(target.navigationLabels),
          <String>['NGE-SEED Target', 'NGE-SEED Cible']);
      expect(target.content.id, 'c-1');
      expect(target.content.source, 'chapter1.xhtml');
    });

    // TC-NAVU-23 [Error guessing]: a navTarget must carry an id.
    test('TC-NAVU-23 [Error guessing]: navTarget without an id is rejected',
        () {
      expect(
        () => const NavigationReader().readNavigationTarget(
          _element('<navTarget>$label</navTarget>'),
        ),
        _throwsMessageContaining('navigation target ID is missing'),
      );
    });

    // TC-NAVU-50 [Boundary value]: an empty id is rejected like an absent one.
    test('TC-NAVU-50 [Boundary]: navTarget with an empty id is rejected', () {
      expect(
        () => const NavigationReader().readNavigationTarget(
          _element('<navTarget id="">$label</navTarget>'),
        ),
        _throwsMessageContaining('navigation target ID is missing'),
      );
    });

    // TC-NAVU-28 [Error guessing]: a navTarget with a content but no label is
    // refused by the label guard.
    test(
        'TC-NAVU-28 [Error guessing]: a content-only navTarget is rejected '
        'for its missing label', () {
      expect(
        () => const NavigationReader().readNavigationTarget(
          _element('<navTarget id="nt-1">'
              '<content src="chapter1.xhtml"/></navTarget>'),
        ),
        _throwsMessageContaining(
            'navigation target: at least one navLabel element is required'),
      );
    });

    // TC-NAVU-24 [Boundary value]: a childless navTarget has no label either,
    // and is refused by the same guard.
    test(
        'TC-NAVU-24 [Boundary]: a childless navTarget is rejected for its '
        'missing label', () {
      expect(
        () => const NavigationReader()
            .readNavigationTarget(_element('<navTarget id="nt-1"/>')),
        _throwsMessageContaining(
            'navigation target: at least one navLabel element is required'),
      );
    });

    // TC-NAVU-51 [Boundary value]: `playOrder` and `<content>`, which NCX
    // requires, read '' and a sourceless content when absent; `value` and
    // `class` are optional and read null.
    test(
        'TC-NAVU-51 [Boundary]: a navTarget with only an id and a label '
        'reads its fallbacks', () {
      final EpubNavigationTarget target = const NavigationReader()
          .readNavigationTarget(_element('<navTarget id="nt-1">$label'
              '</navTarget>'));

      expect(target.id, 'nt-1');
      expect(target.value, isNull);
      expect(target.className, isNull);
      expect(target.playOrder, '');
      expect(_labelTexts(target.navigationLabels), <String>['NGE-SEED Target']);
      expect(target.content.id, isNull);
      expect(target.content.source, isNull);
    });

    // TC-NAVU-52 [Error guessing]: the children are read in document order,
    // so of two malformed children the first is the one reported.
    for (final MapEntry<String, String> order in <String, String>{
      '$_malformedLabel$_malformedContent': _labelMissing,
      '$_malformedContent$_malformedLabel': _sourceMissing,
    }.entries) {
      test(
        'TC-NAVU-52 [Error guessing]: the first malformed navTarget child is '
        'reported (${order.value})',
        () {
          expect(
            () => const NavigationReader().readNavigationTarget(
              _element('<navTarget id="nt-1">${order.key}</navTarget>'),
            ),
            _throwsMessageContaining(order.value),
          );
        },
      );
    }
  });

  group('NavigationReader.readNavigationList', () {
    const String listLabel =
        '<navLabel><text>NGE-SEED Illustrations</text></navLabel>';
    const String listTarget = '<navTarget id="nt-1" playOrder="4">'
        '<navLabel><text>NGE-SEED Figure 1</text></navLabel>'
        '<content src="chapter1.xhtml#fig-1"/>'
        '</navTarget>';

    // TC-NAVU-25 [Boundary value]: a childless navList reads its attributes
    // and two empty lists.
    test('TC-NAVU-25 [Boundary]: reads id and class from a childless navList',
        () {
      final EpubNavigationList list =
          const NavigationReader().readNavigationList(
        _element('<navList id="nl-1" class="illustrations"/>'),
      );

      expect(list.id, 'nl-1');
      expect(list.className, 'illustrations');
      expect(list.navigationLabels, isEmpty);
      expect(list.navigationTargets, isEmpty);
    });

    // TC-NAVU-26 [Scenario/use-case]: a navList carrying a navLabel and a
    // navTarget reads both, and skips foreign children.
    test('TC-NAVU-26 [Scenario]: a navList reads its labels and its targets',
        () {
      final EpubNavigationList list =
          const NavigationReader().readNavigationList(
        _element('<navList id="nl-1" class="illustrations">'
            '$listLabel<notATarget id="ignored"/>$listTarget</navList>'),
      );

      expect(list.id, 'nl-1');
      expect(list.className, 'illustrations');
      expect(_labelTexts(list.navigationLabels),
          <String>['NGE-SEED Illustrations']);
      final EpubNavigationTarget target = list.navigationTargets.single;
      expect(target.id, 'nt-1');
      expect(target.playOrder, '4');
      expect(
          _labelTexts(target.navigationLabels), <String>['NGE-SEED Figure 1']);
      expect(target.content.source, 'chapter1.xhtml#fig-1');
    });

    // TC-NAVU-53 [Equivalence partitioning]: NCX requires both a navLabel
    // and a navTarget; a navList missing either reads with that list empty
    // rather than refusing the book. `id` and `class` are optional.
    for (final MapEntry<String, List<int>> shape in <String, List<int>>{
      listLabel: <int>[1, 0],
      listTarget: <int>[0, 1],
    }.entries) {
      test(
        'TC-NAVU-53 [Equivalence partitioning]: a navList with '
        '${shape.value[0]} label(s) and ${shape.value[1]} target(s) reads '
        'the other list empty',
        () {
          final EpubNavigationList list = const NavigationReader()
              .readNavigationList(_element('<navList>${shape.key}</navList>'));

          expect(list.id, isNull);
          expect(list.className, isNull);
          expect(list.navigationLabels, hasLength(shape.value[0]));
          expect(list.navigationTargets, hasLength(shape.value[1]));
        },
      );
    }
  });

  group('NavigationReader.readNavigationContentV3', () {
    // TC-NAVU-29 [Equivalence partitioning]: `navBase` is prefixed onto a
    // relative href, but ONLY when the href does not already carry it — every
    // full-book EPUB3 fixture elsewhere in this suite uses hrefs that need
    // the prefix, so the "already prefixed" combination (non-empty navBase
    // AND an href that already starts with it) is tried only here. Getting
    // this wrong double-prefixes the href instead of leaving it alone.
    test(
        'TC-NAVU-29 [Equivalence partitioning]: an href already carrying '
        'navBase is left unprefixed', () {
      final EpubNavigationContent content =
          const NavigationReader().readNavigationContentV3(
        _element('<a id="c-1" href="OEBPS/chapter1.xhtml"/>'),
        'OEBPS/',
      );

      expect(content.id, 'c-1');
      expect(content.source, 'OEBPS/chapter1.xhtml');
    });

    // TC-NAVU-54 [Equivalence partitioning]: the other combinations of href
    // and navBase — an empty navBase leaves the href alone, a relative href
    // is joined onto navBase and normalised, and no href at all (a heading)
    // reads a null source whatever the base.
    for (final _ContentV3Case row in const <_ContentV3Case>[
      _ContentV3Case(
        node: '<a href="chapter1.xhtml"/>',
        navBase: '',
        source: 'chapter1.xhtml',
      ),
      _ContentV3Case(
        node: '<a href="chapter1.xhtml"/>',
        navBase: 'OEBPS/',
        source: 'OEBPS/chapter1.xhtml',
      ),
      _ContentV3Case(
        node: '<a href="../chapter1.xhtml"/>',
        navBase: 'OEBPS/text/',
        source: 'OEBPS/chapter1.xhtml',
      ),
      _ContentV3Case(node: '<a/>', navBase: 'OEBPS/'),
      _ContentV3Case(node: '<span>NGE-SEED Heading</span>', navBase: ''),
    ]) {
      test(
        'TC-NAVU-54 [Equivalence partitioning]: ${row.node} under navBase '
        '"${row.navBase}" reads source ${row.source}',
        () {
          final EpubNavigationContent content = const NavigationReader()
              .readNavigationContentV3(_element(row.node), row.navBase);

          expect(content.id, isNull);
          expect(content.source, row.source);
        },
      );
    }
  });

  group('NavigationReader.extractContentPath', () {
    // TC-NAVU-27 [Equivalence partitioning]: the helper joins a base and a
    // ref, normalising `./` and `../` segments. It has no caller inside the
    // package — see the report — but it is public API, so its contract is
    // pinned here.
    for (final List<String> row in <List<String>>[
      <String>['OEBPS/text', 'chapter1.xhtml', 'OEBPS/text/chapter1.xhtml'],
      <String>['OEBPS/text/', 'chapter1.xhtml', 'OEBPS/text/chapter1.xhtml'],
      <String>['OEBPS/text', './chapter1.xhtml', 'OEBPS/text/chapter1.xhtml'],
      <String>[
        'OEBPS/text',
        '../images/cover.png',
        'OEBPS/images/cover.png',
      ],
      <String>['OEBPS', '../chapter1.xhtml', 'chapter1.xhtml'],
    ]) {
      test(
        'TC-NAVU-27 [Equivalence partitioning]: "${row[0]}" + "${row[1]}" '
        'resolves to "${row[2]}"',
        () {
          expect(
            const NavigationReader().extractContentPath(row[0], row[1]),
            row[2],
          );
        },
      );
    }
  });
}
