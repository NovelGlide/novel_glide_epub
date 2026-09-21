// Element-level behaviour of `NavigationReader`'s public readers, driven
// straight from XML fragments — the style of `spine_direction_test.dart`.
//
// The archive-level guards live in
// `navigation_reader_archive_errors_test.dart`; this file covers what each
// reader does with one node, including the guards that a whole-book fixture
// cannot reach without also tripping an earlier one.
import 'package:novel_glide_epub/src/readers/navigation_reader.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_content.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_doc_author.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_doc_title.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_head.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_label.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_list.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_map.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_list.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_target.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_target_type.dart';
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

void main() {
  group('NavigationReader.readNavigationContent', () {
    // TC-NAVU-1 [Scenario/use-case]: an NCX `content` node yields id + src.
    test('TC-NAVU-1 [Scenario]: reads id and src from a content node', () {
      final EpubNavigationContent content = const NavigationReader()
          .readNavigationContent(
              _element('<content id="c-1" src="chapter1.xhtml#a"/>'));

      expect(content.Id, 'c-1');
      expect(content.Source, 'chapter1.xhtml#a');
    });

    // TC-NAVU-2 [Boundary value]: src absent and src empty are both rejected
    // — the two sides of the `Source == null || Source.isEmpty` guard.
    for (final String node in <String>[
      '<content id="c-1"/>',
      '<content id="c-1" src=""/>',
    ]) {
      test(
          'TC-NAVU-2 [Boundary]: content without a usable src is rejected '
          '($node)', () {
        expect(
          () => const NavigationReader().readNavigationContent(_element(node)),
          _throwsMessageContaining('content source is missing'),
        );
      });
    }
  });

  group('NavigationReader.readNavigationHead', () {
    // TC-NAVU-3 [Scenario/use-case]: meta name/content/scheme are read and
    // non-meta children ignored.
    test(
        'TC-NAVU-3 [Scenario]: reads meta attributes and skips non-meta '
        'children', () {
      final EpubNavigationHead head =
          const NavigationReader().readNavigationHead(
        _element('<head>'
            '<meta name="dtb:uid" content="NGE-SEED-UID" scheme="uuid"/>'
            '<notMeta name="ignored"/>'
            '</head>'),
      );

      expect(head.Metadata, hasLength(1));
      expect(head.Metadata!.single.Name, 'dtb:uid');
      expect(head.Metadata!.single.Content, 'NGE-SEED-UID');
      expect(head.Metadata!.single.Scheme, 'uuid');
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

      expect(head.Metadata!.single.Content, isEmpty);
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

      expect(title.Titles, <String>['NGE-SEED A', 'NGE-SEED B']);
    });

    test('TC-NAVU-8 [Scenario]: docAuthor collects text children only', () {
      final EpubNavigationDocAuthor author =
          const NavigationReader().readNavigationDocAuthor(
        _element('<docAuthor><img src="x"/><text>NGE-SEED Author</text>'
            '</docAuthor>'),
      );

      expect(author.Authors, <String>['NGE-SEED Author']);
    });
  });

  group('NavigationReader.readNavigationLabel', () {
    // TC-NAVU-9 [Scenario/use-case]: the label's text element supplies Text.
    test('TC-NAVU-9 [Scenario]: reads the label text element', () {
      final EpubNavigationLabel label =
          const NavigationReader().readNavigationLabel(
        _element('<navLabel><text>NGE-SEED Label</text></navLabel>'),
      );

      expect(label.Text, 'NGE-SEED Label');
    });

    // TC-NAVU-10 [Error guessing]: a label with no text element is rejected.
    test(
        'TC-NAVU-10 [Error guessing]: label without a text element is '
        'rejected', () {
      expect(
        () => const NavigationReader().readNavigationLabel(
          _element('<navLabel><notText>x</notText></navLabel>'),
        ),
        _throwsMessageContaining('label text element is missing'),
      );
    });

    // TC-NAVU-11 [Scenario/use-case]: the EPUB3 label reader takes the node's
    // own text, trimmed — there is no nested text element in a nav document.
    test('TC-NAVU-11 [Scenario]: the V3 label reader trims the node text', () {
      final EpubNavigationLabel label =
          const NavigationReader().readNavigationLabelV3(
        _element('<a href="chapter1.xhtml">  NGE-SEED V3 Label  </a>'),
      );

      expect(label.Text, 'NGE-SEED V3 Label');
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
        _throwsMessageContaining('at least one navigation label'),
      );
    });

    test('TC-NAVU-14 [Error guessing]: navPoint without content is rejected',
        () {
      expect(
        () => const NavigationReader().readNavigationPoint(
          _element('<navPoint id="np-1">$label</navPoint>'),
        ),
        _throwsMessageContaining('should contain content'),
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

      expect(map.Points, hasLength(1));
      expect(map.Points!.single.Id, 'np-1');
    });
  });

  group('NavigationReader.readNavigationPageTarget', () {
    const String label = '<navLabel><text>NGE-SEED 1</text></navLabel>';

    // TC-NAVU-17 [Equivalence partitioning]: every declared page-target type
    // string resolves to its enum value.
    for (final MapEntry<String, EpubNavigationPageTargetType> pair
        in <String, EpubNavigationPageTargetType>{
      'front': EpubNavigationPageTargetType.FRONT,
      'normal': EpubNavigationPageTargetType.NORMAL,
      'special': EpubNavigationPageTargetType.SPECIAL,
    }.entries) {
      test(
        'TC-NAVU-17 [Equivalence partitioning]: page target type '
        '"${pair.key}" resolves to ${pair.value}',
        () {
          final EpubNavigationPageTarget target =
              const NavigationReader().readNavigationPageTarget(
            _element('<pageTarget id="pt-1" value="1" type="${pair.key}" '
                'class="pagenum" playOrder="2">$label</pageTarget>'),
          );

          expect(target.Type, pair.value);
          expect(target.Id, 'pt-1');
          expect(target.Value, '1');
          expect(target.Class, 'pagenum');
          expect(target.PlayOrder, '2');
        },
      );
    }

    // TC-NAVU-18 [Error guessing]: `type="undefined"` is the one value the
    // guard rejects — an unrecognised string leaves Type null and passes,
    // which TC-NAVU-19 pins.
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

    // TC-NAVU-19 [Error guessing]: an unrecognised type string is accepted
    // with a null Type — pinning current behaviour, not endorsing it.
    test(
        'TC-NAVU-19 [Error guessing]: unrecognised page target type leaves '
        'Type null instead of throwing', () {
      final EpubNavigationPageTarget target =
          const NavigationReader().readNavigationPageTarget(
        _element('<pageTarget id="pt-1" type="nge-seed-unknown">$label'
            '</pageTarget>'),
      );

      expect(target.Type, isNull);
    });

    // TC-NAVU-20 [Error guessing]: a page target needs at least one navLabel.
    test(
        'TC-NAVU-20 [Error guessing]: page target without a navLabel is '
        'rejected', () {
      expect(
        () => const NavigationReader().readNavigationPageTarget(
          _element('<pageTarget id="pt-1" type="normal">'
              '<content src="chapter1.xhtml"/></pageTarget>'),
        ),
        _throwsMessageContaining('at least one navLabel element is required'),
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

      expect(list.Targets, hasLength(1));
      expect(list.Targets!.single.Id, 'pt-1');
    });
  });

  group('NavigationReader.readNavigationTarget', () {
    const String label = '<navLabel><text>NGE-SEED Target</text></navLabel>';

    // TC-NAVU-22 [Error guessing]: KNOWN DEFECT, pinned not fixed. Every
    // well-formed navTarget throws: `EpubNavigationTarget.NavigationLabels`
    // is never initialised, and the child walk appends to it through `!`.
    // The reader therefore has no success path at all — reported to the
    // caller; the fix belongs in lib/.
    test(
        'TC-NAVU-22 [Error guessing]: navTarget with a navLabel throws '
        'TypeError (uninitialised NavigationLabels)', () {
      expect(
        () => const NavigationReader().readNavigationTarget(
          _element('<navTarget id="nt-1" value="v" class="c" playOrder="3">'
              '$label<content src="chapter1.xhtml"/></navTarget>'),
        ),
        throwsA(isA<TypeError>()),
      );
    });

    // TC-NAVU-23 [Error guessing]: the id guard runs before the child walk,
    // so it is the one navTarget error that still surfaces as an Exception.
    test('TC-NAVU-23 [Error guessing]: navTarget without an id is rejected',
        () {
      expect(
        () => const NavigationReader().readNavigationTarget(
          _element('<navTarget>$label</navTarget>'),
        ),
        _throwsMessageContaining('navigation target ID is missing'),
      );
    });

    // TC-NAVU-28 [Scenario/use-case]: a `content` child IS read into the
    // target before the null list trips — the attributes and content of a
    // navTarget are parsed correctly, only the label list is unusable.
    test(
        'TC-NAVU-28 [Scenario]: a content-only navTarget still parses its'
        'content before the label list trips', () {
      expect(
        () => const NavigationReader().readNavigationTarget(
          _element('<navTarget id="nt-1">'
              '<content src="chapter1.xhtml"/></navTarget>'),
        ),
        throwsA(isA<TypeError>()),
      );
    });

    // TC-NAVU-24 [Error guessing]: with no children at all the same null list
    // trips the `NavigationLabels!.isEmpty` guard itself, so the intended
    // 'at least one navLabel' Exception is unreachable.
    test(
        'TC-NAVU-24 [Error guessing]: childless navTarget throws TypeError '
        'at the label-count guard instead of its own Exception', () {
      expect(
        () => const NavigationReader().readNavigationTarget(
          _element('<navTarget id="nt-1"/>'),
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('NavigationReader.readNavigationList', () {
    // TC-NAVU-25 [Scenario/use-case]: attributes are read; a navList with no
    // children is the only shape that survives (see TC-NAVU-26).
    test('TC-NAVU-25 [Scenario]: reads id and class from a childless navList',
        () {
      final EpubNavigationList list =
          const NavigationReader().readNavigationList(
        _element('<navList id="nl-1" class="illustrations"/>'),
      );

      expect(list.Id, 'nl-1');
      expect(list.Class, 'illustrations');
    });

    // TC-NAVU-26 [Error guessing]: KNOWN DEFECT, pinned not fixed —
    // `EpubNavigationList` leaves NavigationLabels/NavigationTargets null and
    // this reader appends through `!`, so either child shape is a TypeError.
    // Reported to the caller; the fix belongs in lib/.
    for (final String child in <String>[
      '<navLabel><text>NGE-SEED Label</text></navLabel>',
      '<navTarget id="nt-1"><navLabel><text>NGE-SEED Target</text></navLabel></navTarget>',
    ]) {
      test(
        'TC-NAVU-26 [Error guessing]: navList child throws TypeError on the '
        'uninitialised list (${child.substring(0, 9)})',
        () {
          expect(
            () => const NavigationReader().readNavigationList(
              _element('<navList id="nl-1">$child</navList>'),
            ),
            throwsA(isA<TypeError>()),
          );
        },
      );
    }
  });

  group('NavigationReader.readNavigationContentV3', () {
    // TC-NAVU-29 [Equivalence partitioning]: `navBase` is prefixed onto a
    // relative href, but ONLY when the href does not already carry it — every
    // full-book EPUB3 fixture elsewhere in this suite uses hrefs that need
    // the prefix, so the "already prefixed" combination (non-empty navBase
    // AND an href that already starts with it) was never tried. Getting this
    // wrong double-prefixes the href instead of leaving it alone.
    test(
        'TC-NAVU-29 [Equivalence partitioning]: an href already carrying '
        'navBase is left unprefixed', () {
      final EpubNavigationContent content =
          const NavigationReader().readNavigationContentV3(
        _element('<a id="c-1" href="OEBPS/chapter1.xhtml"/>'),
        'OEBPS/',
      );

      expect(content.Source, 'OEBPS/chapter1.xhtml');
    });
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
