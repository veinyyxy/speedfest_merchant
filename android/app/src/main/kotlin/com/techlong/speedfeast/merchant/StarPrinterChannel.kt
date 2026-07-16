package com.techlong.speedfeast.merchant

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
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
            "probe" -> runPrinterOperation(call, result, printImage = false)
            "printImage" -> runPrinterOperation(call, result, printImage = true)
            else -> result.notImplemented()
        }
    }

    private fun runPrinterOperation(
        call: MethodCall,
        result: MethodChannel.Result,
        printImage: Boolean
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
                    if (printImage) {
                        val imageBytes = arguments["imageBytes"] as? ByteArray
                            ?: throw IllegalArgumentException("Receipt image is required.")
                        require(imageBytes.isNotEmpty()) { "Receipt image is empty." }
                        val paperWidthDots = readInt(arguments, "paperWidthDots", 576)
                            .coerceIn(256, 832)
                        val feedLines = readInt(arguments, "feedLines", 2)
                            .coerceIn(0, 20)
                        val cutMode = readString(arguments, "cutMode").lowercase()
                        val bitmap = BitmapFactory.decodeByteArray(
                            imageBytes,
                            0,
                            imageBytes.size
                        ) ?: throw IllegalArgumentException("Receipt image is invalid.")
                        try {
                            Log.d(
                                TAG,
                                "printImage bitmap=${bitmap.width}x${bitmap.height} " +
                                    "bytes=${imageBytes.size} paperWidthDots=$paperWidthDots"
                            )
                            val imageParameter = ImageParameter(bitmap, paperWidthDots)
                                .setEffectDiffusion(false)
                                .setThreshold(THERMAL_IMAGE_THRESHOLD)
                            val printerBuilder = PrinterBuilder()
                                .actionPrintImage(imageParameter)
                            if (feedLines > 0) {
                                printerBuilder.actionFeedLine(feedLines)
                            }
                            if (cutMode == "partial") {
                                printerBuilder.actionCut(CutType.Partial)
                            }
                            val commands = StarXpandCommandBuilder()
                                .addDocument(
                                    DocumentBuilder().addPrinter(printerBuilder)
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
        const val TAG = "StarPrinterChannel"
        const val CHANNEL_NAME = "speedfeast_merchant/star_printer"
        const val THERMAL_IMAGE_THRESHOLD = 210
    }
}
