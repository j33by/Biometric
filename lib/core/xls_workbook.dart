// Template-preserving BIFF8 (.xls) engine.
//
// Reads a workbook into records + a cell grid, lets callers change cell
// values, and writes it back.  Everything that is not a plain cell record
// (formatting, column widths, merged cells, sheet protection, formulas and
// their cached results, ...) is carried over byte for byte.  Only the
// BOUNDSHEET offsets and the DIMENSIONS record are recomputed.

import 'dart:collection';
import 'dart:typed_data';

const int _tBof = 0x0809;
const int _tEof = 0x000A;
const int _tBoundsheet = 0x0085;
const int _tSst = 0x00FC;
const int _tContinue = 0x003C;
const int _tDim = 0x0200;
const int _tRow = 0x0208;
const int _tIndex = 0x020B;
const int _tDbcell = 0x00D7;
const int _tBlank = 0x0201;
const int _tNumber = 0x0203;
const int _tLabel = 0x0204;
const int _tBoolErr = 0x0205;
const int _tRk = 0x027E;
const int _tLabelSst = 0x00FD;
const int _tMulBlank = 0x00BE;
const int _tMulRk = 0x00BD;
const int _tFormula = 0x0006;
const int _tRString = 0x00D6;
const int _tString = 0x0207;
const int _tShrFmla = 0x04BC;
const int _tArray = 0x0221;
const int _tTable = 0x0236;

int _u16(Uint8List d, int o) => d[o] | (d[o + 1] << 8);
int _u32(Uint8List d, int o) => d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24);

class Rec {
  final int type;
  final Uint8List data;
  Rec(this.type, this.data);
  int get size => 4 + data.length;
}

/// One cell.  [value] is null (blank), double, or String.  Cells that this
/// engine does not model (formulas, errors, rich text) keep their [raw]
/// records and are written back untouched.
class XlsCell {
  int xf;
  Object? value;
  List<Rec>? raw;
  XlsCell(this.xf, [this.value, this.raw]);
}

class XlsSheet {
  String name;
  final bool isWorksheet;
  final SplayTreeMap<int, SplayTreeMap<int, XlsCell>> rows = SplayTreeMap();

  List<Rec> _records; // original records (non-worksheets are written as-is)
  int _regionStart = -1;
  int _regionEnd = -1; // exclusive

  XlsSheet._(this.name, this.isWorksheet, this._records);

  XlsCell? cell(int r, int c) => rows[r]?[c];
  Object? value(int r, int c) => rows[r]?[c]?.value;

  String? text(int r, int c) {
    final v = value(r, c);
    if (v == null) return null;
    if (v is String) return v;
    if (v is double) return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return v.toString();
  }

  double? number(int r, int c) {
    final v = value(r, c);
    if (v is double) return v;
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// Sets a value, keeping the existing cell's style (or [xf] if new).
  void set(int r, int c, Object? v, {int? xf}) {
    final row = rows.putIfAbsent(r, () => SplayTreeMap());
    final existing = row[c];
    final Object? norm = v is num ? v.toDouble() : (v is String && v.isEmpty ? null : v);
    if (existing != null) {
      existing.value = norm;
      existing.raw = null;
      if (xf != null) existing.xf = xf;
    } else {
      row[c] = XlsCell(xf ?? 0, norm);
    }
  }

  void clearRowsFrom(int r) {
    final drop = rows.keys.where((k) => k >= r).toList();
    for (final k in drop) {
      rows.remove(k);
    }
  }

  int get lastRow => rows.isEmpty ? -1 : rows.lastKey()!;
}

class XlsWorkbook {
  final List<Rec> _globals;
  final List<XlsSheet> sheets;
  final List<String> sst;

  XlsWorkbook._(this._globals, this.sheets, this.sst);

  XlsSheet? sheetByName(String name) {
    final n = name.trim().toLowerCase();
    for (final s in sheets) {
      if (s.name.trim().toLowerCase() == n) return s;
    }
    return null;
  }

  // -------------------------------------------------------------- parse
  static XlsWorkbook parse(Uint8List data) {
    final subs = <List<Rec>>[];
    final starts = <int>[];
    List<Rec>? cur;
    var depth = 0;
    var pos = 0;
    while (pos + 4 <= data.length) {
      final t = _u16(data, pos);
      final len = _u16(data, pos + 2);
      if (pos + 4 + len > data.length) break;
      if (cur == null && t != _tBof) break;
      if (t == _tBof) {
        if (cur == null) {
          cur = <Rec>[];
          subs.add(cur);
          starts.add(pos);
          depth = 0;
        }
        depth++;
      }
      cur!.add(Rec(t, Uint8List.fromList(data.sublist(pos + 4, pos + 4 + len))));
      if (t == _tEof) {
        depth--;
        if (depth <= 0) cur = null;
      }
      pos += 4 + len;
    }
    if (subs.isEmpty) throw const FormatException('No BIFF workbook stream found');

    final globals = subs[0];
    final sst = _parseSst(globals);

    final sheets = <XlsSheet>[];
    for (final r in globals) {
      if (r.type != _tBoundsheet) continue;
      final off = _u32(r.data, 0);
      final kind = r.data[5];
      final nameLen = r.data[6];
      final flags = r.data[7];
      final name = _readChars(r.data, 8, nameLen, flags & 1 != 0);
      final k = starts.indexOf(off);
      if (k < 1) throw const FormatException('BOUNDSHEET points to unknown stream');
      final sheet = XlsSheet._(name, kind == 0, subs[k]);
      if (kind == 0) _parseCells(sheet, sst);
      sheets.add(sheet);
    }
    return XlsWorkbook._(globals, sheets, sst);
  }

  static String _readChars(Uint8List d, int o, int n, bool wide) {
    final units = <int>[];
    for (var i = 0; i < n; i++) {
      units.add(wide ? _u16(d, o + i * 2) : d[o + i]);
    }
    return String.fromCharCodes(units);
  }

  /// XLUnicodeString at [o]: cch(2) flags(1) [runs(2)] [ext(4)] chars...
  static String _readXlString(Uint8List d, int o) {
    final cch = _u16(d, o);
    final flags = d[o + 2];
    var p = o + 3;
    if (flags & 0x08 != 0) p += 2;
    if (flags & 0x04 != 0) p += 4;
    return _readChars(d, p, cch, flags & 1 != 0);
  }

  static List<String> _parseSst(List<Rec> globals) {
    final idx = globals.indexWhere((r) => r.type == _tSst);
    if (idx < 0) return const [];
    final chunks = <Uint8List>[globals[idx].data];
    for (var i = idx + 1; i < globals.length && globals[i].type == _tContinue; i++) {
      chunks.add(globals[i].data);
    }
    if (chunks[0].length < 8) return const [];
    final unique = _u32(chunks[0], 4);
    final out = <String>[];
    var ci = 0;
    var off = 8;
    while (out.length < unique && ci < chunks.length) {
      if (off >= chunks[ci].length) {
        ci++;
        off = 0;
        continue;
      }
      var d = chunks[ci];
      if (off + 3 > d.length) break;
      final cch = _u16(d, off);
      final flags = d[off + 2];
      off += 3;
      var runs = 0;
      var ext = 0;
      if (flags & 0x08 != 0) {
        runs = _u16(d, off);
        off += 2;
      }
      if (flags & 0x04 != 0) {
        ext = _u32(d, off);
        off += 4;
      }
      var wide = flags & 1 != 0;
      final sb = StringBuffer();
      var left = cch;
      while (left > 0) {
        d = chunks[ci];
        if (off >= d.length) {
          ci++;
          off = 0;
          if (ci >= chunks.length) break;
          d = chunks[ci];
          wide = (d[0] & 1) != 0;
          off = 1;
        }
        final avail = d.length - off;
        final per = wide ? 2 : 1;
        var take = avail ~/ per;
        if (take > left) take = left;
        if (take == 0) {
          off = d.length; // odd trailing byte, move on
          continue;
        }
        for (var k = 0; k < take; k++) {
          sb.writeCharCode(wide ? _u16(d, off) : d[off]);
          off += per;
        }
        left -= take;
      }
      var skip = runs * 4 + ext;
      while (skip > 0 && ci < chunks.length) {
        final avail = chunks[ci].length - off;
        if (avail >= skip) {
          off += skip;
          skip = 0;
        } else {
          skip -= avail;
          ci++;
          off = 0;
        }
      }
      out.add(sb.toString());
    }
    return out;
  }

  static double _rk(int rk) {
    double v;
    if (rk & 2 != 0) {
      var i = (rk & 0xFFFFFFFC) >> 2;
      if (i & 0x20000000 != 0) i -= 0x40000000;
      v = i.toDouble();
    } else {
      final bd = ByteData(8);
      bd.setUint32(0, 0, Endian.little);
      bd.setUint32(4, rk & 0xFFFFFFFC, Endian.little);
      v = bd.getFloat64(0, Endian.little);
    }
    if (rk & 1 != 0) v /= 100;
    return v;
  }

  static bool _isCellType(int t) =>
      t == _tBlank ||
      t == _tNumber ||
      t == _tLabel ||
      t == _tBoolErr ||
      t == _tRk ||
      t == _tLabelSst ||
      t == _tMulBlank ||
      t == _tMulRk ||
      t == _tFormula ||
      t == _tRString;

  static void _parseCells(XlsSheet sheet, List<String> sst) {
    final recs = sheet._records;
    var first = -1;
    var last = -1;
    var i = 0;
    while (i < recs.length) {
      final r = recs[i];
      final d = r.data;
      if (!_isCellType(r.type)) {
        i++;
        continue;
      }
      if (first < 0) first = i;
      var consumed = 1;
      void put(int row, int col, XlsCell c) {
        sheet.rows.putIfAbsent(row, () => SplayTreeMap())[col] = c;
      }

      switch (r.type) {
        case _tBlank:
          put(_u16(d, 0), _u16(d, 2), XlsCell(_u16(d, 4)));
        case _tMulBlank:
          final row = _u16(d, 0);
          final c0 = _u16(d, 2);
          final n = (d.length - 6) ~/ 2;
          for (var k = 0; k < n; k++) {
            put(row, c0 + k, XlsCell(_u16(d, 4 + k * 2)));
          }
        case _tRk:
          put(_u16(d, 0), _u16(d, 2), XlsCell(_u16(d, 4), _rk(_u32(d, 6))));
        case _tMulRk:
          final row = _u16(d, 0);
          final c0 = _u16(d, 2);
          final n = (d.length - 6) ~/ 6;
          for (var k = 0; k < n; k++) {
            final o = 4 + k * 6;
            put(row, c0 + k, XlsCell(_u16(d, o), _rk(_u32(d, o + 2))));
          }
        case _tNumber:
          final v = ByteData.sublistView(d).getFloat64(6, Endian.little);
          put(_u16(d, 0), _u16(d, 2), XlsCell(_u16(d, 4), v));
        case _tLabel:
          put(_u16(d, 0), _u16(d, 2), XlsCell(_u16(d, 4), _readXlString(d, 6)));
        case _tLabelSst:
          final idx = _u32(d, 6);
          put(_u16(d, 0), _u16(d, 2), XlsCell(_u16(d, 4), idx < sst.length ? sst[idx] : ''));
        case _tFormula:
          final group = <Rec>[r];
          while (i + consumed < recs.length &&
              (recs[i + consumed].type == _tString ||
                  recs[i + consumed].type == _tShrFmla ||
                  recs[i + consumed].type == _tArray ||
                  recs[i + consumed].type == _tTable)) {
            group.add(recs[i + consumed]);
            consumed++;
            if (group.last.type == _tString &&
                i + consumed < recs.length &&
                recs[i + consumed].type == _tContinue) {
              group.add(recs[i + consumed]);
              consumed++;
            }
          }
          put(_u16(d, 0), _u16(d, 2), XlsCell(_u16(d, 4), null, group));
        default: // BOOLERR, RSTRING: keep raw
          put(_u16(d, 0), _u16(d, 2), XlsCell(_u16(d, 4), null, [r]));
      }
      i += consumed;
      last = i;
    }
    sheet._regionStart = first;
    sheet._regionEnd = last;
  }

  // -------------------------------------------------------------- build
  static Uint8List _ser(Rec r) {
    final out = Uint8List(4 + r.data.length);
    out[0] = r.type & 0xFF;
    out[1] = r.type >> 8;
    out[2] = r.data.length & 0xFF;
    out[3] = r.data.length >> 8;
    out.setRange(4, out.length, r.data);
    return out;
  }

  static Rec _mk(int type, List<int> data) => Rec(type, Uint8List.fromList(data));

  static List<int> _w16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  static List<int> _w32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

  static Rec _cellRec(int r, int c, XlsCell cell) {
    final v = cell.value;
    if (v is double) {
      final bd = ByteData(8)..setFloat64(0, v, Endian.little);
      return _mk(_tNumber, [..._w16(r), ..._w16(c), ..._w16(cell.xf), ...bd.buffer.asUint8List()]);
    }
    if (v is String) {
      var s = v;
      if (s.length > 255) s = s.substring(0, 255);
      final wide = s.codeUnits.any((u) => u > 0xFF);
      final body = <int>[];
      for (final u in s.codeUnits) {
        body.add(u & 0xFF);
        if (wide) body.add(u >> 8);
      }
      return _mk(_tLabel,
          [..._w16(r), ..._w16(c), ..._w16(cell.xf), ..._w16(s.length), wide ? 1 : 0, ...body]);
    }
    return _mk(_tBlank, [..._w16(r), ..._w16(c), ..._w16(cell.xf)]);
  }

  List<Rec> _sheetRecords(XlsSheet s) {
    if (!s.isWorksheet) return s._records;
    final src = s._records;
    final pre = <Rec>[];
    final post = <Rec>[];
    final rowRecs = <Rec>[];
    final hasRegion = s._regionStart >= 0;
    for (var i = 0; i < src.length; i++) {
      final r = src[i];
      if (r.type == _tIndex || r.type == _tDbcell) continue;
      if (hasRegion && i >= s._regionStart && i < s._regionEnd) {
        if (r.type == _tRow) rowRecs.add(r);
        continue;
      }
      if (hasRegion && i < s._regionStart) {
        pre.add(r);
      } else if (hasRegion) {
        post.add(r);
      } else {
        // no cells originally: insert before the final EOF
        (i == src.length - 1 ? post : pre).add(r);
      }
    }

    var minR = 1 << 30, maxR = -1, minC = 1 << 30, maxC = -1;
    final cells = <Rec>[];
    s.rows.forEach((r, cols) {
      cols.forEach((c, cell) {
        if (r < minR) minR = r;
        if (r > maxR) maxR = r;
        if (c < minC) minC = c;
        if (c > maxC) maxC = c;
        if (cell.raw != null) {
          cells.addAll(cell.raw!);
        } else {
          cells.add(_cellRec(r, c, cell));
        }
      });
    });
    if (maxR < 0) {
      minR = 0;
      maxR = -1;
      minC = 0;
      maxC = -1;
    }
    for (var i = 0; i < pre.length; i++) {
      if (pre[i].type == _tDim) {
        pre[i] = _mk(_tDim, [..._w32(minR), ..._w32(maxR + 1), ..._w16(minC), ..._w16(maxC + 1), 0, 0]);
      }
    }
    return [...pre, ...rowRecs, ...cells, ...post];
  }

  Uint8List build() {
    final sheetRecs = sheets.map(_sheetRecords).toList();
    final sheetBytes = sheetRecs.map((rs) {
      final b = BytesBuilder(copy: false);
      for (final r in rs) {
        b.add(_ser(r));
      }
      return b.toBytes();
    }).toList();

    var globalsLen = 0;
    for (final r in _globals) {
      globalsLen += r.size;
    }
    final offsets = <int>[];
    var o = globalsLen;
    for (final b in sheetBytes) {
      offsets.add(o);
      o += b.length;
    }

    final out = BytesBuilder(copy: false);
    var k = 0;
    for (final r in _globals) {
      if (r.type == _tBoundsheet && k < offsets.length) {
        final d = Uint8List.fromList(r.data);
        final v = offsets[k++];
        d[0] = v & 0xFF;
        d[1] = (v >> 8) & 0xFF;
        d[2] = (v >> 16) & 0xFF;
        d[3] = (v >> 24) & 0xFF;
        out.add(_ser(Rec(r.type, d)));
      } else {
        out.add(_ser(r));
      }
    }
    for (final b in sheetBytes) {
      out.add(b);
    }
    return out.toBytes();
  }
}
