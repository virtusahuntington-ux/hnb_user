import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';

import 'dart:typed_data';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase with project credentials
  await Supabase.initialize(
    url: 'https://kbkzbdidvpskssjvoxor.supabase.co',
    publishableKey: 'sb_publishable_6GyZDug44K5tjxkFGSbqZw_sZkd_3Yp',
  );

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

final GoRouter _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (c, s) => const UploadScreen()),
    GoRoute(
      path: '/client/:clientId',
      builder: (c, s) =>
          ClientDashboard(clientId: s.pathParameters['clientId'] ?? ''),
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      title: 'HNB Cherished Moments',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B4E3E),
          primary: const Color(0xFF1B4E3E),
          secondary: const Color(0xFFD4AF37),
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F4F2),
        cardTheme: const CardThemeData(elevation: 0),
      ),
    );
  }
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final List<String> categories = ['Sessions', 'Cultural Events'];
  String selectedCategory = 'Sessions';

  final commentController = TextEditingController();
  bool isUploading = false;

  // Stored Future to prevent page blinking during setStates
  late Future<List<Map<String, dynamic>>> _momentsFuture;

  @override
  void initState() {
    super.initState();
    _refreshFeed();
  }

  void _refreshFeed() {
    setState(() {
      _momentsFuture = supabase
          .from('moments')
          .select()
          .order('created_at', ascending: false);
    });
  }

  Future<void> _uploadMedia() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) return;

    final bytes = result.files.single.bytes!;
    final fileName = result.files.single.name;

    setState(() => isUploading = true);
    try {
      final fileExt = fileName.split('.').last;
      final uniqueFileName =
          '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'uploads/$uniqueFileName';

      // 1. Upload to Supabase Storage
      await supabase.storage
          .from('hnb_bucket')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: result.files.single.extension == 'mp4'
                  ? 'video/mp4'
                  : 'image/jpeg',
            ),
          );

      // 2. Generate hardcoded public URL with the new project ID
      final publicUrl =
          'https://kbkzbdidvpskssjvoxor.supabase.co/storage/v1/object/public/hnb_bucket/$filePath';
      // 3. Insert record into Supabase 'moments'
      await supabase.from('moments').insert({
        'client_name': 'client1',
        'media_url': publicUrl,
        'comment': commentController.text.trim(),
        'category': selectedCategory,
      });

      commentController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Memory shared successfully! 🎉'),
            ],
          ),
          backgroundColor: const Color(0xFF1B4E3E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      _refreshFeed();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) {
        setState(() => isUploading = false);
      }
    }
  }

  // Action: Edit Memory (Photo + Comment Text)
  // Action: Edit Memory (Larger Photo Display + Comment Text)
  Future<void> _showEditDialog(
    dynamic id,
    String currentComment,
    String currentMediaUrl,
  ) async {
    final editController = TextEditingController(text: currentComment);

    try {
      Uint8List? newFileBytes;
      String? newFileName;
      bool isSaving = false;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              // Robust file picker helper for web dialogs
              Future<void> pickNewFile() async {
                try {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.any,
                    withData: true,
                  );

                  if (result != null && result.files.single.bytes != null) {
                    setDialogState(() {
                      newFileBytes = result.files.single.bytes;
                      newFileName = result.files.single.name;
                    });
                  }
                } catch (e) {
                  debugPrint('File picker error: $e');
                }
              }

              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Text(
                  'Edit Memory',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                content: SizedBox(
                  width:
                      420, // Expanded dialog width for a larger visual canvas
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Memory Photo:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: newFileBytes != null
                                    ? Image.memory(
                                        newFileBytes!,
                                        width: double.infinity,
                                        height: 260, // Significantly larger photo display
                                        fit: BoxFit.cover,
                                      )
                                    : Image.network(
                                        currentMediaUrl,
                                        width: double.infinity,
                                        height: 260, // Significantly larger photo display
                                        cacheWidth: 800,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: double.infinity,
                                          height: 260,
                                          color: Colors.grey.shade200,
                                          child: const Icon(
                                            Icons.broken_image,
                                            size: 50,
                                          ),
                                        ),
                                      ),
                              ),
                              Positioned(
                                bottom: 12,
                                right: 12,
                                child: InkWell(
                                  onTap: pickNewFile,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1B4E3E),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: TextButton.icon(
                            icon: const Icon(Icons.photo_library, size: 16),
                            label: Text(
                              newFileBytes != null
                                  ? 'Change Selection'
                                  : 'Replace Photo',
                            ),
                            onPressed: pickNewFile,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: editController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Memory Caption',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('CANCEL'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: isSaving
                        ? null
                        : () async {
                            setDialogState(() => isSaving = true);
                            try {
                              String updatedMediaUrl = currentMediaUrl;

                              if (newFileBytes != null && newFileName != null) {
                                final fileExt = newFileName!.split('.').last;
                                final uniqueName =
                                    '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
                                final filePath = 'uploads/$uniqueName';

                                await supabase.storage
                                    .from('hnb_bucket')
                                    .uploadBinary(
                                      filePath,
                                      newFileBytes!,
                                      fileOptions: FileOptions(
                                        contentType: fileExt == 'mp4'
                                            ? 'video/mp4'
                                            : 'image/jpeg',
                                      ),
                                    );

                                updatedMediaUrl =
                                    'https://kbkzbdidvpskssjvoxor.supabase.co/storage/v1/object/public/hnb_bucket/$filePath';
                              }

                              // Explicitly target the record ID using .eq('id', id)
                              await supabase
                                  .from('moments')
                                  .update({
                                    'comment': editController.text.trim(),
                                    'media_url': updatedMediaUrl,
                                  })
                                  .eq('id', id);

                              if (!mounted) return;
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Memory updated successfully!'),
                                ),
                              );
                              _refreshFeed();
                            } catch (e) {
                              setDialogState(() => isSaving = false);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Update failed: $e')),
                              );
                            }
                          },
                    child: isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('UPDATE'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      // Ensures the controller is always disposed, preventing memory leaks
      editController.dispose();
    }
  }

  // Delete Action: Dynamic verification against security_settings table
  Future<void> _showDeleteDialog(dynamic id) async {
    final codeController = TextEditingController();
    String? errorMessage;
    bool isVerifying = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Delete Memory',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter authorization code to confirm deletion:'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Security Code',
                      errorText: errorMessage,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isVerifying
                      ? null
                      : () async {
                          setDialogState(() {
                            isVerifying = true;
                            errorMessage = null;
                          });

                          try {
                            final inputCode = codeController.text.trim();

                            // Fetch security code from Database
                            final response = await supabase
                                .from('security_settings')
                                .select('passcode')
                                .limit(1)
                                .maybeSingle();

                            final validCode =
                                response?['passcode']?.toString() ?? '1127';

                            if (inputCode == validCode) {
                              // Explicitly delete matching record ID using .eq('id', id)
                              await supabase
                                  .from('moments')
                                  .delete()
                                  .eq('id', id);

                              if (!mounted) return;
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Memory deleted successfully.'),
                                ),
                              );
                              _refreshFeed();
                            } else {
                              setDialogState(() {
                                isVerifying = false;
                                errorMessage = 'Invalid Code. Access Denied.';
                              });
                            }
                          } catch (e) {
                            setDialogState(() {
                              isVerifying = false;
                              errorMessage = 'Verification error: $e';
                            });
                          }
                        },
                  child: isVerifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('DELETE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      body: isWide
          ? Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(child: _buildUploadForm(theme)),
                ),
                Container(
                  width: 440,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 20,
                        offset: const Offset(-4, 0),
                      ),
                    ],
                  ),
                  child: _buildFeedSection(theme, isDesktop: true),
                ),
              ],
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildUploadForm(theme),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 12.0,
                    ),
                    child: Divider(color: Colors.grey.shade300, height: 1),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 650),
                    padding: const EdgeInsets.all(20.0),
                    child: _buildFeedSection(theme, isDesktop: false),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildUploadForm(ThemeData theme) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24.0),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 25,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 36,
                  horizontal: 24,
                ),
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1B4E3E), Color(0xFF0F2E24)],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: Color(0xFFD4AF37),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'HNB CHERISHED MOMENTS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Capture and share beautiful memories',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'CATEGORY',
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAF9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      items: categories
                          .map(
                            (cat) => DropdownMenuItem(
                              value: cat,
                              child: Text(
                                cat,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => selectedCategory = val);
                      },
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: commentController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Add a note or memory caption...',
                        alignLabelWithHint: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAF9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    isUploading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(
                              Icons.cloud_upload_outlined,
                              color: Color(0xFFD4AF37),
                            ),
                            label: const Text(
                              'UPLOAD & SHARE MEMORY',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            onPressed: _uploadMedia,
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedSection(ThemeData theme, {required bool isDesktop}) {
    return Padding(
      padding: EdgeInsets.all(isDesktop ? 24.0 : 0),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [
              Row(
                children: [
                  Container(
                    width: 8,

                    height: 8,

                    decoration: const BoxDecoration(
                      color: Color(0xFFD4AF37),

                      shape: BoxShape.circle,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Text(
                    'ALL SHARED MEMORIES',

                    style: TextStyle(
                      fontWeight: FontWeight.w800,

                      fontSize: 13,

                      letterSpacing: 1.1,

                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),

              IconButton(
                icon: const Icon(Icons.refresh, size: 20),

                onPressed: _refreshFeed,

                tooltip: 'Refresh feed',
              ),
            ],
          ),

          const SizedBox(height: 16),

          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _momentsFuture,

              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final list = snapshot.data ?? [];

                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,

                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),

                        const SizedBox(height: 12),

                        Text(
                          'No memories shared yet.',

                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),

                  cacheExtent: 500,

                  addAutomaticKeepAlives: true,

                  addRepaintBoundaries: true,

                  itemCount: list.length,

                  separatorBuilder: (_, __) => const SizedBox(height: 16),

                  itemBuilder: (context, index) {
                    final data = list[index];

                    final dynamic recordId = data['id'];

                    final category = (data['category'] ?? 'Sessions')
                        .toString();

                    final isSession = category == 'Sessions';

                    final String comment = data['comment'] ?? '';

                    final String mediaUrl = data['media_url'] ?? '';

                    return RepaintBoundary(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius: BorderRadius.circular(16),

                          border: Border.all(color: Colors.grey.shade200),

                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),

                              blurRadius: 10,

                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            // Medium-Sized Photo Preview with Overlay Actions

                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16),
                                  ),

                                  child: Image.network(
                                    mediaUrl,

                                    width: double.infinity,

                                    height: 180, // Medium recognition size

                                    cacheWidth: 600,

                                    fit: BoxFit.cover,

                                    errorBuilder: (_, __, ___) => Container(
                                      width: double.infinity,

                                      height: 180,

                                      color: Colors.grey.shade200,

                                      child: const Icon(
                                        Icons.broken_image,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),

                                Positioned(
                                  top: 10,

                                  left: 10,

                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),

                                    decoration: BoxDecoration(
                                      color:
                                          (isSession
                                                  ? const Color(0xFF1B4E3E)
                                                  : const Color(0xFF8C701B))
                                              .withOpacity(0.9),

                                      borderRadius: BorderRadius.circular(8),
                                    ),

                                    child: Text(
                                      category.toUpperCase(),

                                      style: const TextStyle(
                                        fontSize: 10,

                                        fontWeight: FontWeight.bold,

                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),

                                Positioned(
                                  top: 10,

                                  right: 10,

                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,

                                    children: [
                                      Material(
                                        color: Colors.white.withOpacity(0.9),

                                        shape: const CircleBorder(),

                                        child: InkWell(
                                          customBorder: const CircleBorder(),

                                          onTap: () => _showEditDialog(
                                            recordId,
                                            comment,
                                            mediaUrl,
                                          ),

                                          child: const Padding(
                                            padding: EdgeInsets.all(7.0),

                                            child: Icon(
                                              Icons.edit_outlined,
                                              size: 16,
                                              color: Color(0xFF1B4E3E),
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 8),

                                      Material(
                                        color: Colors.white.withOpacity(0.9),

                                        shape: const CircleBorder(),

                                        child: InkWell(
                                          customBorder: const CircleBorder(),

                                          onTap: () =>
                                              _showDeleteDialog(recordId),

                                          child: const Padding(
                                            padding: EdgeInsets.all(7.0),

                                            child: Icon(
                                              Icons.delete_outline,
                                              size: 16,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // Memory Caption Section
                            Padding(
                              padding: const EdgeInsets.all(12.0),

                              child: Text(
                                comment.isEmpty ? 'No caption added' : comment,

                                maxLines: 3,

                                overflow: TextOverflow.ellipsis,

                                style: TextStyle(
                                  fontSize: 13,

                                  fontWeight: FontWeight.w600,

                                  color: Colors.grey.shade800,

                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ClientDashboard extends StatelessWidget {
  final String clientId;
  const ClientDashboard({super.key, required this.clientId});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 1000 ? 3 : (width > 600 ? 2 : 1);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            expandedHeight: 220,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '${clientId.toUpperCase()} MEMORIES',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1B4E3E), Color(0xFF1E293B)],
                  ),
                ),
              ),
            ),
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: supabase
                .from('moments')
                .select()
                .eq('client_name', clientId)
                .order('created_at', ascending: false),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Text('Your cherished memories are on their way!'),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.all(24.0),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final data = list[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Image.network(
                              data['media_url'] ?? '',
                              cacheWidth: 400,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Center(child: Icon(Icons.broken_image)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['comment'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.favorite,
                                      size: 16,
                                      color: Colors.redAccent,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      (data['category'] ?? 'SESSIONS')
                                          .toString()
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }, childCount: list.length),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
