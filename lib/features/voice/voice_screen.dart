import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Added Supabase package import
import 'voice_intents.dart'; 
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final _supabaseClient = Supabase.instance.client;
  
  bool _isRecording = false;
  bool _isLoading = false;
  String _statusMessage = 'Tap the microphone to speak a transaction';
  String _lastSpokenText = '';

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        setState(() {
          _statusMessage = 'Microphone permission denied. Please allow access.';
        });
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/voice_intent.m4a';

      const config = RecordConfig(encoder: AudioEncoder.aacLc);
      await _audioRecorder.start(config, path: path);

      setState(() {
        _isRecording = true;
        _statusMessage = 'Listening to shopkeeper...';
        _lastSpokenText = '';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error initializing recording: $e';
      });
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isLoading = true;
        _statusMessage = 'Processing audio transaction stream...';
      });

      if (path != null) {
        final file = File(path);
        
        final sizeInBytes = await file.length();
        if (sizeInBytes > 4 * 1024 * 1024) { 
          throw Exception('Audio file duration or size footprint exceeds bounds.');
        }

        // 🚀 REAL CONNECTION: Send audio file to Safwan's live backend Edge Function
        String mockTranscript = "";
        dynamic matchedProductFromDB;
        
        try {
          final response = await _supabaseClient.functions.invoke(
            'parse-voice-intent', 
            body: file,
          );
          
          final Map<String, dynamic> responseData = jsonDecode(response.data);
          mockTranscript = responseData['transcript'] ?? "Pepsi 500ml bechbo";
          matchedProductFromDB = responseData['matchedProduct'];
        } catch (e) {
          // Fallback simulation text if Safwan hasn't fully deployed the edge endpoint yet
          mockTranscript = "Pepsi 500ml bechbo"; 
        }

        if (!mounted) return;

        setState(() {
          _isLoading = false;
        });
        
        // 2. Pass the phrase through our custom local variation matcher
        final detectedIntent = VoiceIntentMatcher.parseTranscript(mockTranscript);

        setState(() {
          _lastSpokenText = mockTranscript;
        });

        // 3. Process flow dynamically based on Bangla keyword intent maps
// 3. Process flow dynamically based on Bangla keyword intent maps
        switch (detectedIntent) {
          case VoiceIntentType.sell:
            // 📊 Day 7 Real Model Alignment: Extract values if DB returned a match, otherwise use placeholder
            final Product simulatedProduct = (matchedProductFromDB != null) 
              ? Product.fromJson(matchedProductFromDB)
              : const Product(
                  id: 'sample-pepsi-id',
                  shopId: 'sample-shop-id', // Added required shopId field
                  name: 'Pepsi 500ml',
                  quantity: 12.0, 
                  buyingPrice: 40.0,      // Fixed field name from costPrice -> buyingPrice
                  sellingPrice: 50.0,
                );

            _showConfirmationCard(
              context,
              productName: simulatedProduct.name,
              quantity: 1,
              onConfirm: () async {
                setState(() => _isLoading = true);
                
                const double quantitySold = 1.0;
                final Product updatedProduct = simulatedProduct.copyWith(
                  quantity: simulatedProduct.quantity - quantitySold,
                );

                try {
                  // 📊 REAL DATABASE TRANSACTION: Update the database directly via Supabase client
                  await _supabaseClient
                      .from('products') 
                      .update({'quantity': updatedProduct.quantity})
                      .eq('id', updatedProduct.id);

                  if (!mounted) return;

                  final double profitMargin = updatedProduct.marginPerUnit * quantitySold;
                  final bool warningTriggered = updatedProduct.isLowStock;

                  setState(() {
                    _isLoading = false;
                    _statusMessage = 'Sale complete! Margin: ৳${profitMargin.toStringAsFixed(2)}\n'
                        'Remaining: ${updatedProduct.quantityLabel}';
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: warningTriggered ? Colors.orange.shade900 : Colors.green,
                      duration: const Duration(seconds: 4),
                      content: Text(
                        warningTriggered 
                          ? '⚠️ LOW STOCK ALERT: Only ${updatedProduct.quantityLabel} remaining!'
                          : 'Sold ${quantitySold.toStringAsFixed(0)}x ${updatedProduct.name} successfully pushed to DB!',
                        ),
                      ),
                    );
                } catch (dbError) {
                  if (!mounted) return;
                  setState(() {
                    _isLoading = false;
                    _statusMessage = 'Database sync error: $dbError';
                  });
                }
              },
            );
            setState(() {
              _statusMessage = 'Match evaluated successfully via intent: "Sell"';
            });
            break;

          case VoiceIntentType.total:
            setState(() {
              _statusMessage = 'Hishab intent triggered! Finalizing grand bill summary...';
            });
            break;

          case VoiceIntentType.cancel:
            setState(() {
              _statusMessage = 'Baad/Cancel intent triggered. Clearing current workspace.';
            });
            break;

          case VoiceIntentType.unknown:
            setState(() {
              _statusMessage = 'Unclear command pattern. Try saying "bechbo" or "hishab".';
            });
            break;
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Transaction parse failure: $e';
      });
    }
  }

  void _showConfirmationCard(
    BuildContext context, {
    required String productName,
    required int quantity,
    required VoidCallback onConfirm,
  }) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Confirm Voice Transaction',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'Sell $quantity x $productName?',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onConfirm();
                    },
                    child: const Text('Confirm Entry'),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Assistant')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              if (_lastSpokenText.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Heard: "$_lastSpokenText"',
                  style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.blueAccent),
                ),
              ],
              const SizedBox(height: 48),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                GestureDetector(
                  onTap: _toggleRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording ? Colors.red : Colors.blue,
                      boxShadow: [
                        BoxShadow(
                          color: (_isRecording ? Colors.red : Colors.blue).withValues(alpha: 0.4),
                          blurRadius: 15,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}