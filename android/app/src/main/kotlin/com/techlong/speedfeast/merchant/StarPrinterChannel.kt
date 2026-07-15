package com.techlong.speedfeast.merchant

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.ceil
import kotlin.math.max
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.starmicronics.stario10.InterfaceType
import com.starmicronics.stario10.StarConnectionSettings
import com.starmicronics.stario10.StarPrinter
import com.starmicronics.stario10.starxpandcommand.DocumentBuilder
import com.starmicronics.stario10.starxpandcommand.PrinterBuilder
import com.starmicronics.stario10.starxpandcommand.StarXpandCommandBuilder
import com.starmicronics.stario10.starxpandcommand.printer.CutType
import com.starmicronics.stario10.starxpandcommand.printer.ImageParameter

class StarPrinterChannel(
    private val applicationContext: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun register() {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> runPrinterOperation(call, result, printText = false)
            "printText" -> runPrinterOperation(call, result, printText = true)
            else -> result.notImplemented()
        }
    }

    private fun runPrinterOperation(
        call: MethodCall,
        result: MethodChannel.Result,
        printText: Boolean
    ) {
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null) {
            result.error("invalid_arguments", "Printer arguments are required.", null)
            return
        }

        scope.launch {
            try {
                val settings = connectionSettings(arguments)
                val printer = StarPrinter(settings, applicationContext)
                try {
                    printer.openAsync().await()
                    if (printText) {
                        val text = readString(arguments, "text")
                        val paperWidthDots = readInt(arguments, "paperWidthDots", 576)
                            .coerceIn(256, 832)
                        val lineWidth = readInt(arguments, "lineWidth", 48)
                            .coerceIn(24, 64)
                        val bitmap = renderReceiptBitmap(text, paperWidthDots, lineWidth)
                        try {
                            val commands = StarXpandCommandBuilder()
                                .addDocument(
                                    DocumentBuilder().addPrinter(
                                        PrinterBuilder()
                                            .actionPrintImage(
                                                ImageParameter(bitmap, paperWidthDots)
                                            )
                                            .actionFeedLine(2)
                                            .actionCut(CutType.Partial)
                                    )
                                )
                                .getCommands()
                            printer.printAsync(commands).await()
                        } finally {
                            bitmap.recycle()
                        }
                    }
                } finally {
                    runCatching { printer.closeAsync().await() }
                }
                withContext(Dispatchers.Main) { result.success(null) }
            } catch (error: Exception) {
                val message = error.message?.takeIf { it.isNotBlank() }
                    ?: error.javaClass.simpleName
                withContext(Dispatchers.Main) {
                    result.error("star_printer_error", message, error.javaClass.name)
                }
            }
        }
    }

    private fun connectionSettings(arguments: Map<*, *>): StarConnectionSettings {
        val identifier = readString(arguments, "identifier")
        require(identifier.isNotBlank()) { "Printer address is empty." }
        val interfaceType = when (readString(arguments, "interface").lowercase()) {
            "bluetooth" -> InterfaceType.Bluetooth
            "lan" -> InterfaceType.Lan
            else -> throw IllegalArgumentException(
                "Star printing requires a Bluetooth or LAN printer."
            )
        }
        return StarConnectionSettings(interfaceType, identifier)
    }

    private fun renderReceiptBitmap(
        text: String,
        paperWidthDots: Int,
        lineWidth: Int
    ): Bitmap {
        val horizontalMargin = if (paperWidthDots <= 384) 10f else 16f
        val printableWidth = paperWidthDots - (horizontalMargin * 2)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.NORMAL)
            textSize = 24f
        }
        val referenceWidth = paint.measureText("M".repeat(lineWidth))
        if (referenceWidth > printableWidth) {
            paint.textSize *= printableWidth / referenceWidth
        }
        paint.textSize = max(14f, paint.textSize)

        val lines = text.replace("\r\n", "\n")
            .replace('\r', '\n')
            .split('\n')
            .flatMap { wrapLine(it, paint, printableWidth) }
            .ifEmpty { listOf("") }
        val lineHeight = ceil(paint.fontSpacing.toDouble()).toInt().coerceAtLeast(1)
        val verticalMargin = lineHeight
        val bitmapHeight = (verticalMargin * 2 + lineHeight * lines.size)
            .coerceAtLeast(lineHeight * 3)
        val bitmap = Bitmap.createBitmap(
            paperWidthDots,
            bitmapHeight,
            Bitmap.Config.ARGB_8888
        )
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        var baseline = verticalMargin - paint.fontMetrics.top
        for (line in lines) {
            canvas.drawText(line, horizontalMargin, baseline, paint)
            baseline += lineHeight
        }
        return bitmap
    }

    private fun wrapLine(line: String, paint: Paint, width: Float): List<String> {
        if (line.isEmpty()) return listOf("")
        val wrapped = mutableListOf<String>()
        var remaining = line
        while (remaining.isNotEmpty()) {
            val count = paint.breakText(remaining, true, width, null).coerceAtLeast(1)
            wrapped += remaining.substring(0, count)
            remaining = remaining.substring(count)
        }
        return wrapped
    }

    private fun readString(arguments: Map<*, *>, key: String): String {
        return arguments[key]?.toString()?.trim() ?: ""
    }

    private fun readInt(arguments: Map<*, *>, key: String, fallback: Int): Int {
        val value = arguments[key]
        return when (value) {
            is Number -> value.toInt()
            else -> value?.toString()?.toIntOrNull() ?: fallback
        }
    }

    private companion object {
        const val CHANNEL_NAME = "speedfeast_merchant/star_printer"
    }
}
