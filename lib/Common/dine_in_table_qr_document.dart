import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../Models/merchant_dining_table.dart';

Future<Uint8List> buildDineInTableQrPdf({
  required MerchantDiningTable table,
  PdfPageFormat pageFormat = PdfPageFormat.a6,
}) async {
  final document = pw.Document();
  final qrSize = math
      .min(pageFormat.width * 0.58, pageFormat.height * 0.48)
      .clamp(120.0, 260.0)
      .toDouble();

  document.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.Center(
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              'SpeedFeast',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Scan to order', style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 18),
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: table.effectiveQrPayload,
              width: qrSize,
              height: qrSize,
              drawText: false,
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              table.tableNumber,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    ),
  );
  return document.save();
}
