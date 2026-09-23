// `XmlAttributeReader` — the one attribute lookup every reader goes through.
//
// Real books write `opf:role` as often as `role`, and `playorder` as often as
// `playOrder`, so the lookup ignores both the namespace prefix and the case of
// the attribute name. What this file pins is exactly that normalisation, plus
// which value survives when two attributes normalise to one key.
//
// Techniques: equivalence partitioning (prefixed vs. bare, upper vs. lower
// case), boundary value (no attributes, an absent name), error guessing (two
// attributes that normalise to one key).
import 'package:novel_glide_epub/src/utils/xml_attribute_reader.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

const XmlAttributeReader _reader = XmlAttributeReader();

const String _opfNamespace = 'xmlns:opf="http://www.idpf.org/2007/opf"';

XmlElement _element(String xml) => XmlDocument.parse(xml).rootElement;

void main() {
  group('XmlAttributeReader.read', () {
    // TC-XAR-1 [Equivalence partitioning]: a bare attribute is found by its
    // own name.
    test('TC-XAR-1 [Equivalence partitioning]: a bare attribute is read', () {
      expect(
        _reader.read(
            _element('<creator role="aut">NGE-SEED</creator>'), 'role'),
        'aut',
      );
    });

    // TC-XAR-2 [Equivalence partitioning]: a prefixed attribute is found by
    // its local name, so `opf:role` answers a lookup for `role`.
    test(
        'TC-XAR-2 [Equivalence partitioning]: a prefixed attribute is read by '
        'its local name', () {
      expect(
        _reader.read(
          _element('<creator $_opfNamespace opf:role="edt">NGE-SEED</creator>'),
          'role',
        ),
        'edt',
      );
    });

    // TC-XAR-3 [Equivalence partitioning]: the attribute name's case does not
    // matter — `playOrder` answers a lookup for `playorder`.
    test(
        'TC-XAR-3 [Equivalence partitioning]: an attribute is read whatever '
        'the case of its name', () {
      expect(
        _reader.read(_element('<navPoint playOrder="7"/>'), 'playorder'),
        '7',
      );
      expect(
        _reader.read(
            _element('<item xmlns:OPF="http://www.idpf.org/2007/opf" '
                'OPF:MEDIA-TYPE="image/png"/>'),
            'media-type'),
        'image/png',
      );
    });

    // TC-XAR-4 [Boundary value]: an absent attribute reads null, not ''.
    test('TC-XAR-4 [Boundary]: an absent attribute reads null', () {
      expect(
          _reader.read(_element('<creator role="aut"/>'), 'file-as'), isNull);
      expect(_reader.read(_element('<creator/>'), 'role'), isNull);
    });

    // TC-XAR-5 [Boundary value]: an attribute present but empty reads '' —
    // telling empty from absent is the caller's decision.
    test('TC-XAR-5 [Boundary]: an empty attribute reads the empty string', () {
      expect(_reader.read(_element('<creator role=""/>'), 'role'), '');
    });

    // TC-XAR-6 [Boundary value]: the lookup key is compared to the
    // LOWER-CASED attribute name, so the caller passes it in lower case; an
    // upper-case key matches nothing.
    test('TC-XAR-6 [Boundary]: the lookup key is expected in lower case', () {
      expect(_reader.read(_element('<navPoint playOrder="7"/>'), 'playOrder'),
          isNull);
    });

    // TC-XAR-7 [Error guessing]: `role` and `opf:role` on one element are
    // distinct XML attributes but one key here; the later one wins, in both
    // orders.
    test(
        'TC-XAR-7 [Error guessing]: of two attributes sharing a local name, '
        'the later wins', () {
      expect(
        _reader.read(
          _element('<creator $_opfNamespace opf:role="aut" role="edt"/>'),
          'role',
        ),
        'edt',
      );
      expect(
        _reader.read(
          _element('<creator $_opfNamespace role="edt" opf:role="aut"/>'),
          'role',
        ),
        'aut',
      );
    });
  });

  group('XmlAttributeReader.readAll', () {
    // TC-XAR-8 [Scenario/use-case]: every attribute is returned, keyed by
    // its lower-cased local name, in document order — the namespace
    // declaration included, as it is an attribute of the element.
    test(
        'TC-XAR-8 [Scenario]: every attribute is keyed by lower-cased local '
        'name', () {
      final Map<String, String> attributes = _reader.readAll(
        _element('<meta $_opfNamespace NAME="cover" opf:Content="img-1" '
            'scheme="NGE-SEED"/>'),
      );

      expect(attributes, <String, String>{
        'opf': 'http://www.idpf.org/2007/opf',
        'name': 'cover',
        'content': 'img-1',
        'scheme': 'NGE-SEED',
      });
      expect(attributes.keys.toList(),
          <String>['opf', 'name', 'content', 'scheme']);
    });

    // TC-XAR-9 [Boundary value]: an element with no attributes reads an
    // empty map, not null.
    test('TC-XAR-9 [Boundary]: no attributes read an empty map', () {
      expect(_reader.readAll(_element('<meta/>')), isEmpty);
    });

    // TC-XAR-10 [Error guessing]: two attributes that normalise to one key
    // leave one entry, holding the later value.
    test(
        'TC-XAR-10 [Error guessing]: attributes normalising to one key leave '
        'the later value', () {
      expect(
        _reader.readAll(
          _element('<creator $_opfNamespace opf:role="aut" ROLE="edt"/>'),
        ),
        <String, String>{
          'opf': 'http://www.idpf.org/2007/opf',
          'role': 'edt',
        },
      );
    });
  });
}
