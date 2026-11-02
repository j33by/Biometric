// Minimal OLE2 / Compound File Binary reader + writer.
//
// Only what is needed to open a legacy .xls produced by the biometric
// device software and write it back: top-level streams, 512-byte sectors on
// write, any sector size on read.  Pure Dart (no Flutter, no packages).

import 'dart:typed_data';

const int _endOfChain = 0xFFFFFFFE;
const int _freeSect = 0xFFFFFFFF;
const int _fatSect = 0xFFFFFFFD;
const int _noStream = 0xFFFFFFFF;

class CfbStream {
  final String name;
  Uint8List data;
  CfbStream(this.name, this.data);
}

class CfbFile {
  final List<CfbStream> streams;
  final Uint8List rootClsid;
  CfbFile(this.streams, Uint8List? clsid) : rootClsid = clsid ?? Uint8List(16);

  CfbStream? find(String name) {
    for (final s in streams) {
      if (s.name == name) return s;
    }
    return null;
  }
}

class _DirEntry {
  String name = '';
  int type = 0;
  int left = _noStream;
  int right = _noStream;
  int child = _noStream;
  int start = 0;
  int size = 0;
  int color = 1;
  Uint8List clsid = Uint8List(16);
}

class Cfb {
  static const List<int> _sig = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];

  // ---------------------------------------------------------------- read
  static CfbFile read(Uint8List b) {
    if (b.length < 512) throw const FormatException('File too small for OLE2');
    for (var i = 0; i < 8; i++) {
      if (b[i] != _sig[i]) throw const FormatException('Not an OLE2 (.xls) file');
    }
    final bd = ByteData.sublistView(b);
    final secSize = 1 << bd.getUint16(0x1E, Endian.little);
    final miniSize = 1 << bd.getUint16(0x20, Endian.little);
    final numFat = bd.getUint32(0x2C, Endian.little);
    final dirStart = bd.getUint32(0x30, Endian.little);
    final miniCutoff = bd.getUint32(0x38, Endian.little);
    final miniFatStart = bd.getUint32(0x3C, Endian.little);
    final difatStart = bd.getUint32(0x44, Endian.little);
    final numDifat = bd.getUint32(0x48, Endian.little);

    final fatSectors = <int>[];
    for (var i = 0; i < 109; i++) {
      final v = bd.getUint32(0x4C + i * 4, Endian.little);
      if (v < 0xFFFFFFFA) fatSectors.add(v);
    }
    var d = difatStart;
    var left = numDifat;
    while (left > 0 && d < 0xFFFFFFFA) {
      final off = (d + 1) * secSize;
      if (off + secSize > b.length) break;
      for (var j = 0; j < secSize ~/ 4 - 1; j++) {
        final v = bd.getUint32(off + j * 4, Endian.little);
        if (v < 0xFFFFFFFA) fatSectors.add(v);
      }
      d = bd.getUint32(off + secSize - 4, Endian.little);
      left--;
    }

    final fat = <int>[];
    for (final s in fatSectors.take(numFat == 0 ? fatSectors.length : numFat)) {
      final off = (s + 1) * secSize;
      if (off + secSize > b.length) continue;
      for (var j = 0; j < secSize ~/ 4; j++) {
        fat.add(bd.getUint32(off + j * 4, Endian.little));
      }
    }

    Uint8List readChain(int start) {
      final out = BytesBuilder(copy: false);
      var s = start;
      var guard = 0;
      while (s < 0xFFFFFFFA) {
        final off = (s + 1) * secSize;
        if (off >= b.length) break;
        final end = off + secSize > b.length ? b.length : off + secSize;
        out.add(Uint8List.sublistView(b, off, end));
        if (s >= fat.length) break;
        s = fat[s];
        if (++guard > fat.length + 2) {
          throw const FormatException('Corrupt FAT chain');
        }
      }
      return out.toBytes();
    }

    final dirBytes = readChain(dirStart);
    final dbd = ByteData.sublistView(dirBytes);
    final entries = <_DirEntry>[];
    for (var i = 0; i + 128 <= dirBytes.length; i += 128) {
      final e = _DirEntry();
      final nameLen = dbd.getUint16(i + 0x40, Endian.little);
      final chars = nameLen >= 2 ? (nameLen ~/ 2) - 1 : 0;
      final units = <int>[];
      for (var k = 0; k < chars && k < 31; k++) {
        units.add(dbd.getUint16(i + k * 2, Endian.little));
      }
      e.name = String.fromCharCodes(units);
      e.type = dirBytes[i + 0x42];
      e.color = dirBytes[i + 0x43];
      e.left = dbd.getUint32(i + 0x44, Endian.little);
      e.right = dbd.getUint32(i + 0x48, Endian.little);
      e.child = dbd.getUint32(i + 0x4C, Endian.little);
      e.clsid = Uint8List.fromList(dirBytes.sublist(i + 0x50, i + 0x60));
      e.start = dbd.getUint32(i + 0x74, Endian.little);
      e.size = dbd.getUint32(i + 0x78, Endian.little);
      entries.add(e);
    }
    if (entries.isEmpty || entries[0].type != 5) {
      throw const FormatException('OLE2 root entry missing');
    }
    final root = entries[0];

    // mini stream + mini FAT
    final miniStream = root.size > 0 ? readChain(root.start) : Uint8List(0);
    final miniFat = <int>[];
    if (miniFatStart < 0xFFFFFFFA) {
      final mf = readChain(miniFatStart);
      final mbd = ByteData.sublistView(mf);
      for (var i = 0; i + 4 <= mf.length; i += 4) {
        miniFat.add(mbd.getUint32(i, Endian.little));
      }
    }
    Uint8List readMini(int start, int size) {
      final out = BytesBuilder(copy: false);
      var s = start;
      var guard = 0;
      while (s < 0xFFFFFFFA) {
        final off = s * miniSize;
        if (off >= miniStream.length) break;
        final end = off + miniSize > miniStream.length ? miniStream.length : off + miniSize;
        out.add(Uint8List.sublistView(miniStream, off, end));
        if (s >= miniFat.length) break;
        s = miniFat[s];
        if (++guard > miniFat.length + 2) throw const FormatException('Corrupt mini FAT');
      }
      final all = out.toBytes();
      return size < all.length ? Uint8List.sublistView(all, 0, size) : all;
    }

    // in-order walk of the red/black tree under the root
    final streams = <CfbStream>[];
    final seen = <int>{};
    void walk(int idx) {
      if (idx == _noStream || idx >= entries.length || !seen.add(idx)) return;
      final e = entries[idx];
      walk(e.left);
      if (e.type == 2) {
        Uint8List data;
        if (e.size < miniCutoff) {
          data = readMini(e.start, e.size);
        } else {
          final all = readChain(e.start);
          data = all.length > e.size ? all.sublist(0, e.size) : all;
        }
        streams.add(CfbStream(e.name, Uint8List.fromList(data)));
      }
      walk(e.right);
    }

    walk(root.child);
    return CfbFile(streams, root.clsid);
  }

  // --------------------------------------------------------------- write
  static int _cmpNames(String a, String b) {
    if (a.length != b.length) return a.length - b.length;
    final ua = a.toUpperCase();
    final ub = b.toUpperCase();
    return ua.compareTo(ub);
  }

  static Uint8List write(CfbFile file) {
    const secSize = 512;
    final streams = file.streams;

    // Pad every stream so that none lives in the mini stream.
    final padded = <Uint8List>[];
    final sizes = <int>[];
    for (final s in streams) {
      final len = s.data.length;
      final logical = len < 4096 ? 4096 : len;
      final alloc = ((logical + secSize - 1) ~/ secSize) * secSize;
      final p = Uint8List(alloc)..setRange(0, len, s.data);
      padded.add(p);
      sizes.add(logical);
    }

    final entryCount = streams.length + 1;
    final dirSecs = (entryCount + 3) ~/ 4;
    var dataSecs = 0;
    for (final p in padded) {
      dataSecs += p.length ~/ secSize;
    }
    var fatSecs = 1;
    while (fatSecs * 128 < dataSecs + dirSecs + fatSecs) {
      fatSecs++;
    }
    if (fatSecs > 109) {
      throw StateError('Workbook too large for this writer (max ~7 MB)');
    }
    final total = dataSecs + fatSecs + dirSecs;
    final out = Uint8List(512 + total * secSize);
    final bd = ByteData.sublistView(out);

    // FAT
    final fat = List<int>.filled(fatSecs * 128, _freeSect);
    var cursor = 0;
    final starts = <int>[];
    for (final p in padded) {
      final n = p.length ~/ secSize;
      starts.add(cursor);
      for (var i = 0; i < n; i++) {
        fat[cursor + i] = i == n - 1 ? _endOfChain : cursor + i + 1;
      }
      cursor += n;
    }
    final fatStart = cursor;
    for (var i = 0; i < fatSecs; i++) {
      fat[fatStart + i] = _fatSect;
    }
    cursor += fatSecs;
    final dirStart = cursor;
    for (var i = 0; i < dirSecs; i++) {
      fat[dirStart + i] = i == dirSecs - 1 ? _endOfChain : dirStart + i + 1;
    }

    // header
    for (var i = 0; i < 8; i++) {
      out[i] = _sig[i];
    }
    bd.setUint16(0x18, 0x003E, Endian.little);
    bd.setUint16(0x1A, 3, Endian.little);
    bd.setUint16(0x1C, 0xFFFE, Endian.little);
    bd.setUint16(0x1E, 9, Endian.little);
    bd.setUint16(0x20, 6, Endian.little);
    bd.setUint32(0x2C, fatSecs, Endian.little);
    bd.setUint32(0x30, dirStart, Endian.little);
    bd.setUint32(0x38, 4096, Endian.little);
    bd.setUint32(0x3C, _endOfChain, Endian.little);
    bd.setUint32(0x40, 0, Endian.little);
    bd.setUint32(0x44, _endOfChain, Endian.little);
    bd.setUint32(0x48, 0, Endian.little);
    for (var i = 0; i < 109; i++) {
      bd.setUint32(0x4C + i * 4, i < fatSecs ? fatStart + i : _freeSect, Endian.little);
    }

    // sector payloads
    for (var i = 0; i < padded.length; i++) {
      out.setRange(512 + starts[i] * secSize, 512 + starts[i] * secSize + padded[i].length, padded[i]);
    }
    for (var i = 0; i < fatSecs; i++) {
      final base = 512 + (fatStart + i) * secSize;
      for (var j = 0; j < 128; j++) {
        bd.setUint32(base + j * 4, fat[i * 128 + j], Endian.little);
      }
    }

    // directory tree (balanced BST over the stream names)
    final dir = List<_DirEntry>.generate(entryCount, (_) => _DirEntry());
    dir[0]
      ..name = 'Root Entry'
      ..type = 5
      ..color = 1
      ..start = _endOfChain
      ..size = 0
      ..clsid = file.rootClsid;
    final order = List<int>.generate(streams.length, (i) => i + 1)
      ..sort((a, b) => _cmpNames(streams[a - 1].name, streams[b - 1].name));
    final depthOf = <int, int>{};
    int build(int lo, int hi, int depth) {
      if (lo > hi) return _noStream;
      final mid = (lo + hi) ~/ 2;
      final idx = order[mid];
      depthOf[idx] = depth;
      dir[idx].left = build(lo, mid - 1, depth + 1);
      dir[idx].right = build(mid + 1, hi, depth + 1);
      return idx;
    }

    dir[0].child = build(0, order.length - 1, 0);
    var levels = 0;
    while ((1 << levels) - 1 < order.length) {
      levels++;
    }
    final perfect = (1 << levels) - 1 == order.length;
    for (var i = 0; i < streams.length; i++) {
      final e = dir[i + 1];
      e.name = streams[i].name;
      e.type = 2;
      e.start = starts[i];
      e.size = sizes[i];
      e.color = (!perfect && depthOf[i + 1] == levels - 1) ? 0 : 1;
    }

    final dbase = 512 + dirStart * secSize;
    for (var i = 0; i < dirSecs * 4; i++) {
      final o = dbase + i * 128;
      if (i < entryCount) {
        final e = dir[i];
        final name = e.name;
        for (var k = 0; k < name.length && k < 31; k++) {
          bd.setUint16(o + k * 2, name.codeUnitAt(k), Endian.little);
        }
        bd.setUint16(o + 0x40, (name.length + 1) * 2, Endian.little);
        out[o + 0x42] = e.type;
        out[o + 0x43] = e.color;
        bd.setUint32(o + 0x44, e.left, Endian.little);
        bd.setUint32(o + 0x48, e.right, Endian.little);
        bd.setUint32(o + 0x4C, e.child, Endian.little);
        out.setRange(o + 0x50, o + 0x60, e.clsid);
        bd.setUint32(o + 0x74, e.start, Endian.little);
        bd.setUint32(o + 0x78, e.size, Endian.little);
      } else {
        bd.setUint32(o + 0x44, _noStream, Endian.little);
        bd.setUint32(o + 0x48, _noStream, Endian.little);
        bd.setUint32(o + 0x4C, _noStream, Endian.little);
      }
    }
    return out;
  }
}
