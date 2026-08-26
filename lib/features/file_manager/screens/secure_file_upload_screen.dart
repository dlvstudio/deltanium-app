import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/features/file_manager/file_upload_service.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/services/app_logger.dart';


class SecureFileUploadScreen extends StatefulWidget {
  const SecureFileUploadScreen({Key? key}) : super(key: key);

  @override
  _SecureFileUploadScreenState createState() => _SecureFileUploadScreenState();
}

class _SecureFileUploadScreenState extends State<SecureFileUploadScreen> {
  final FileUploadService _fileUploadService = FileUploadService();
  final AuthService _authService = AuthService();
  
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  
  List<Map<String, dynamic>> _availableNodes = [];
  Map<String, dynamic>? _selectedNode;
  
  List<Map<String, dynamic>> _selectedMedia = [];
  List<String> _sharedWithUsers = [];
  
  // Auth state
  String? _userPublicKey;
  String? _userMnemonic;
  bool _isLoggedIn = false;
  
  TextEditingController _shareController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadNodes();
  }

  Future<void> _loadUserInfo() async {
    final authInfo = await _authService.getCurrentAuthInfo();
    setState(() {
      _isLoggedIn = authInfo != null;
      if (_isLoggedIn) {
        _userPublicKey = authInfo!['publicKey'];
        _userMnemonic = authInfo['mnemonic'];
        AppLogger.log("SecureFileUpload: Loaded user info, public key: ${_userPublicKey?.substring(0, 10)}...");
      } else {
        AppLogger.log("SecureFileUpload: No user info found, user is not logged in");
      }
    });
  }

  Future<void> _loadNodes() async {
    if (_userPublicKey == null) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/storenode/list'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> nodes = json.decode(response.body);
        setState(() {
          _availableNodes = nodes.cast<Map<String, dynamic>>();
          if (_availableNodes.isNotEmpty) {
            _selectedNode = _availableNodes.first;
          }
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load storage nodes: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading storage nodes: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true, // Make sure we get the bytes data
      );
      
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        setState(() {
          _selectedMedia.add({
            'type': 'file',
            'name': file.name,
            'bytes': file.bytes,
            'size': file.size,
            'extension': file.extension ?? '',
          });
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File selected: ${file.name} (${(file.size / 1024).toStringAsFixed(1)} KB)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  void _addSharedUser() {
    final text = _shareController.text.trim();
    if (text.isNotEmpty) {
      if (!_sharedWithUsers.contains(text)) {
        setState(() {
          _sharedWithUsers.add(text);
          _shareController.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User already added')),
        );
      }
    }
  }

  void _removeSharedUser(int index) {
    setState(() {
      _sharedWithUsers.removeAt(index);
    });
  }

  void _removeMedia(int index) {
    setState(() {
      _selectedMedia.removeAt(index);
    });
  }

  Future<void> _uploadFiles() async {
    if (_selectedNode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a storage node')),
      );
      return;
    }
    
    if (_selectedMedia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file to upload')),
      );
      return;
    }
    
    if (_userPublicKey == null || _userMnemonic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to upload files')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });
    
    try {
      for (final media in _selectedMedia) {
        final fileName = media['name'] as String;
        final fileBytes = media['bytes'] as Uint8List;
        
        // Show a message that we're encrypting the file
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Encrypting file "$fileName" before upload...'),
            duration: const Duration(seconds: 2),
          ),
        );
        
        // Create a test string to verify encryption is working
        if (fileBytes.length < 10) {
          // If this is a very small file, it might be a test - add some logging
          final String testString = String.fromCharCodes(fileBytes);
          AppLogger.log('UPLOAD TEST: Small file detected, content: $testString');
          AppLogger.log('UPLOAD TEST: This content should be encrypted before upload');
        }
        
        final result = await _fileUploadService.uploadEncryptedFile(
          fileData: fileBytes,
          fileName: fileName,
          publicKey: _userPublicKey!,
          mnemonic: _userMnemonic!,
          sharedWithUsers: _sharedWithUsers.isNotEmpty ? _sharedWithUsers : null,
          selectedNode: _selectedNode!,
        );
        
        if (result['success'] == true) {
          setState(() {
            _successMessage = 'File "$fileName" uploaded and encrypted successfully!';
          });
          
          // Show a more detailed message with info about encryption
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File encrypted with AES-256 and uploaded in ${result['blockCount']} secure blocks'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          setState(() {
            _errorMessage = 'Failed to upload ${fileName}: ${result['error']}';
          });
          break;
        }
      }
      
      // Clear selected media if successful
      if (_errorMessage == null) {
        setState(() {
          _selectedMedia.clear();
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure File Upload'),
        backgroundColor: isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white,
        foregroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoggedIn 
        ? _buildUploadForm()
        : _buildLoginPrompt(),
    );
  }
  
  Widget _buildLoginPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'You need to log in to upload encrypted files',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Node selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Step 1: Select Storage Node',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_availableNodes.isEmpty && !_isLoading)
                    const Text('No storage nodes available'),
                  if (_availableNodes.isNotEmpty)
                    DropdownButtonFormField<Map<String, dynamic>>(
                      decoration: const InputDecoration(
                        labelText: 'Storage Node',
                        border: OutlineInputBorder(),
                      ),
                      value: _selectedNode,
                      items: _availableNodes.map((node) {
                        return DropdownMenuItem<Map<String, dynamic>>(
                          value: node,
                          child: Text('${node['name']} (${node['location']})'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedNode = value;
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // File selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Step 2: Select File to Encrypt and Upload',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.file_upload),
                    label: const Text('Select File'),
                  ),
                  const SizedBox(height: 16),
                  if (_selectedMedia.isNotEmpty)
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _selectedMedia.length,
                      itemBuilder: (context, index) {
                        final media = _selectedMedia[index];
                        return ListTile(
                          leading: _buildFileIcon(media),
                          title: Text(media['name'] as String),
                          subtitle: Text(
                            _formatFileSize(media['size'] as int),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _removeMedia(index),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Share with users
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Step 3: Share with Other Users (Optional)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter public keys of users to share this file with:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _shareController,
                          decoration: const InputDecoration(
                            labelText: 'Public Key',
                            border: OutlineInputBorder(),
                            hintText: 'Enter public key to share with',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addSharedUser,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_sharedWithUsers.isNotEmpty)
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _sharedWithUsers.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(
                            _truncateKey(_sharedWithUsers[index]),
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _removeSharedUser(index),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Upload button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _uploadFiles,
              icon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock),
              label: Text(
                _isLoading ? 'Encrypting & Uploading...' : 'Encrypt & Upload File',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            
          if (_successMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _successMessage!,
                style: const TextStyle(color: Colors.green),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildFileIcon(Map<String, dynamic> media) {
    IconData icon = Icons.insert_drive_file;
    Color color = Colors.grey;
    
    final ext = (media['extension'] as String).toLowerCase();
    
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      icon = Icons.image;
      color = Colors.blue;
    } else if (['pdf'].contains(ext)) {
      icon = Icons.picture_as_pdf;
      color = Colors.red;
    } else if (['doc', 'docx'].contains(ext)) {
      icon = Icons.description;
      color = Colors.blue;
    } else if (['xls', 'xlsx'].contains(ext)) {
      icon = Icons.table_chart;
      color = Colors.green;
    } else if (['mp3', 'wav', 'ogg'].contains(ext)) {
      icon = Icons.audio_file;
      color = Colors.purple;
    } else if (['mp4', 'mov', 'avi', 'webm'].contains(ext)) {
      icon = Icons.video_file;
      color = Colors.red;
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      icon = Icons.folder_zip;
      color = Colors.amber;
    }
    
    return Icon(icon, color: color);
  }
  
  String _formatFileSize(int size) {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
  
  String _truncateKey(String key) {
    if (key.length <= 20) return key;
    return key.substring(0, 10) + '...' + key.substring(key.length - 10);
  }
} 
