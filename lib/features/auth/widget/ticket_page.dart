import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Ticket list page — shows user's tickets with status badges.
class TicketListPage extends HookWidget {
  const TicketListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final tickets = useState<List<Map<String, dynamic>>>([]);
    final isLoading = useState(true);
    final error = useState<String?>(null);

    Future<void> load() async {
      isLoading.value = true;
      error.value = null;
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('roxi_token');
        final resp = await AuthService.getWithFallback(
          '/api/tickets?page=1&page_size=50',
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        );
        if (resp != null && resp.statusCode == 200) {
          final data = jsonDecode(utf8.decode(resp.bodyBytes));
          tickets.value = List<Map<String, dynamic>>.from(data['tickets'] ?? []);
        } else {
          error.value = s['networkError'] ?? '加载失败';
        }
      } catch (e) {
        error.value = e.toString();
      }
      isLoading.value = false;
    }

    useEffect(() { load(); return null; }, []);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Text(s['ticketTitle'] ?? '问题反馈',
          style: const TextStyle(color: Colors.black87)),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateTicketPage()),
              );
              load();
            },
          ),
        ],
      ),
      body: isLoading.value
          ? const Center(child: CircularProgressIndicator())
          : error.value != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(error.value!, style: TextStyle(color: Colors.red.shade400)),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: load, child: Text(s['retry'] ?? '重试')),
                ]))
              : tickets.value.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(s['ticketEmpty'] ?? '暂无工单',
                        style: TextStyle(color: Colors.grey.shade500)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const CreateTicketPage()),
                          );
                          load();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(s['ticketNew'] ?? '提交工单'),
                      ),
                    ]))
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: tickets.value.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final t = tickets.value[i];
                          return _TicketTile(
                            ticket: t,
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TicketDetailPage(ticketId: t['id']),
                                ),
                              );
                              load();
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onTap;
  const _TicketTile({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = ticket['status'] as String? ?? 'open';
    final statusLabel = _statusLabel(status);
    final statusColor = _statusColor(status);
    final subject = ticket['subject'] as String? ?? '';
    final replyCount = (ticket['replies'] as List?)?.length ?? 0;
    final createdAt = _fmtDate(ticket['created_at']);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(subject,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Text(statusLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Text('#${ticket['id']}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(width: 12),
              Text(createdAt,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const Spacer(),
              Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text('$replyCount',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ]),
          ]),
        ),
      ),
    );
  }

  static String _statusLabel(String s) {
    final t = AuthI18n.t;
    switch (s) {
      case 'open': return t['ticketStatusOpen'] ?? '待处理';
      case 'replied': return t['ticketStatusReplied'] ?? '已回复';
      case 'user_replied': return t['ticketStatusWaiting'] ?? '等待回复';
      case 'closed': return t['ticketStatusClosed'] ?? '已关闭';
      default: return s;
    }
  }

  static Color _statusColor(String s) {
    switch (s) {
      case 'open': return Colors.blue;
      case 'replied': return Colors.green;
      case 'user_replied': return Colors.orange;
      case 'closed': return Colors.grey;
      default: return Colors.grey;
    }
  }

  static String _fmtDate(dynamic d) {
    if (d == null) return '';
    final s = d.toString();
    return s.length >= 16 ? s.substring(0, 16).replaceFirst('T', ' ') : s;
  }
}

/// Ticket detail page — shows conversation and reply form.
class TicketDetailPage extends HookWidget {
  final int ticketId;
  const TicketDetailPage({super.key, required this.ticketId});

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final ticket = useState<Map<String, dynamic>?>(null);
    final isLoading = useState(true);
    final replyCtrl = useTextEditingController();
    final isSending = useState(false);
    final uploadedImages = useState<List<String>>([]);
    final scrollCtrl = useScrollController();

    Future<void> load() async {
      isLoading.value = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('roxi_token');
        final resp = await AuthService.getWithFallback(
          '/api/tickets/$ticketId',
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        );
        if (resp != null && resp.statusCode == 200) {
          ticket.value = jsonDecode(utf8.decode(resp.bodyBytes));
          // Scroll to bottom after data loads
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scrollCtrl.hasClients) {
              scrollCtrl.animateTo(scrollCtrl.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
            }
          });
        } else {
          // Non-200 response — leave ticket.value as null so the "not found" UI shows
        }
      } catch (e) {
        debugPrint('TicketDetailPage.load error: $e');
      }
      isLoading.value = false;
    }

    Future<void> sendReply() async {
      final text = replyCtrl.text.trim();
      if (text.isEmpty && uploadedImages.value.isEmpty) return;
      isSending.value = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('roxi_token');
        final resp = await AuthService.postWithFallback(
          '/api/tickets/$ticketId/reply',
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'content': text, 'images': uploadedImages.value}),
        );
        if (resp != null && resp.statusCode == 200) {
          replyCtrl.clear();
          uploadedImages.value = [];
          await load();
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s['ticketReplyFail'] ?? '发送失败')));
          }
        }
      } catch (e) {
        debugPrint('TicketDetailPage.sendReply error: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s['ticketReplyFail'] ?? '发送失败')));
        }
      }
      isSending.value = false;
    }

    Future<void> pickAndUpload() async {
      if (uploadedImages.value.length >= 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s['maxImages'] ?? '最多 5 张图片')));
        return;
      }
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1920, imageQuality: 85);
      if (xfile == null) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('roxi_token');
        final url = await _uploadImage(xfile.path, token);
        if (url != null) {
          uploadedImages.value = [...uploadedImages.value, url];
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s['ticketUploadFail'] ?? '图片上传失败')));
          }
        }
      } catch (e) {
        debugPrint('TicketDetailPage.pickAndUpload error: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s['ticketUploadFail'] ?? '图片上传失败')));
        }
      }
    }

    useEffect(() { load(); return null; }, []);

    if (isLoading.value) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0,
          title: Text('#$ticketId', style: const TextStyle(color: Colors.black87)),
          iconTheme: const IconThemeData(color: Colors.black87)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final t = ticket.value;
    if (t == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black87)),
        body: Center(child: Text(s['ticketNotFound'] ?? '工单不存在')),
      );
    }

    final replies = List<Map<String, dynamic>>.from(t['replies'] ?? []);
    final isClosed = t['status'] == 'closed';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Text(t['subject'] ?? '', style: const TextStyle(color: Colors.black87, fontSize: 16),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(16),
            itemCount: replies.length,
            itemBuilder: (ctx, i) => _ReplyBubble(reply: replies[i]),
          ),
        ),
        if (!isClosed) ...[
          // Image preview
          if (uploadedImages.value.isNotEmpty)
            Container(
              height: 60, padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (int i = 0; i < uploadedImages.value.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(clipBehavior: Clip.none, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          '${AuthService.baseUrl}${uploadedImages.value[i]}',
                          height: 50, width: 50, fit: BoxFit.cover)),
                      Positioned(top: -6, right: -6, child: GestureDetector(
                        onTap: () {
                          final list = [...uploadedImages.value];
                          list.removeAt(i);
                          uploadedImages.value = list;
                        },
                        child: Container(
                          width: 18, height: 18,
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 12, color: Colors.white)),
                      )),
                    ]),
                  ),
              ]),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(top: BorderSide(color: Colors.grey.shade200))),
            child: SafeArea(
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.image_outlined, color: Colors.grey.shade600),
                  onPressed: pickAndUpload,
                ),
                Expanded(child: TextField(
                  controller: replyCtrl,
                  maxLines: 3, minLines: 1,
                  decoration: InputDecoration(
                    hintText: s['ticketReplyHint'] ?? '输入回复...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    isDense: true,
                  ),
                )),
                const SizedBox(width: 8),
                isSending.value
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.send_rounded, color: Color(0xFF6c3ce0)),
                        onPressed: sendReply,
                      ),
              ]),
            ),
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(16),
            child: Text(s['ticketClosed'] ?? '工单已关闭',
              style: TextStyle(color: Colors.grey.shade500), textAlign: TextAlign.center),
          ),
      ]),
    );
  }
}

class _ReplyBubble extends StatelessWidget {
  final Map<String, dynamic> reply;
  const _ReplyBubble({required this.reply});

  @override
  Widget build(BuildContext context) {
    final isAdmin = reply['is_admin'] == true;
    final content = reply['content'] as String? ?? '';
    final createdAt = _fmtDate(reply['created_at']);
    final t = AuthI18n.t;

    // Parse content for [img] tags
    final parts = content.split(RegExp(r'(\[img\][^\[]+\[/img\])'));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isAdmin ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: isAdmin ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              Text(isAdmin ? (t['ticketStaff'] ?? '客服') : (t['ticketMe'] ?? '我'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: isAdmin ? const Color(0xFF6c3ce0) : Colors.grey.shade600)),
              const SizedBox(width: 8),
              Text(createdAt, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isAdmin ? const Color(0xFFF3EEFF) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isAdmin ? const Color(0xFF6c3ce0).withOpacity(0.2) : Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final part in parts)
                  if (part.trim().isNotEmpty)
                    _buildContentPart(part, context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentPart(String part, BuildContext context) {
    final imgMatch = RegExp(r'\[img\]([^\[]+)\[/img\]').firstMatch(part);
    if (imgMatch != null) {
      final url = imgMatch.group(1)!;
      final fullUrl = url.startsWith('http') ? url : '${AuthService.baseUrl}$url';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: GestureDetector(
          onTap: () => _showFullImage(context, fullUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 250),
              child: Image.network(fullUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40)),
            ),
          ),
        ),
      );
    }
    return Text(part.trim(),
      style: const TextStyle(fontSize: 14, height: 1.5));
  }

  static void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: InteractiveViewer(
            child: Image.network(url,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 60, color: Colors.white)),
          ),
        ),
      ),
    );
  }

  static String _fmtDate(dynamic d) {
    if (d == null) return '';
    final s = d.toString();
    return s.length >= 16 ? s.substring(0, 16).replaceFirst('T', ' ') : s;
  }
}

/// Create ticket page.
class CreateTicketPage extends HookWidget {
  const CreateTicketPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final subjectCtrl = useTextEditingController();
    final contentCtrl = useTextEditingController();
    final isSending = useState(false);
    final uploadedImages = useState<List<String>>([]);

    Future<void> pickAndUpload() async {
      if (uploadedImages.value.length >= 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s['maxImages'] ?? '最多 5 张图片')));
        return;
      }
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1920, imageQuality: 85);
      if (xfile == null) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('roxi_token');
        final url = await _uploadImage(xfile.path, token);
        if (url != null) {
          uploadedImages.value = [...uploadedImages.value, url];
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s['ticketUploadFail'] ?? '图片上传失败')));
          }
        }
      } catch (e) {
        debugPrint('CreateTicketPage.pickAndUpload error: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s['ticketUploadFail'] ?? '图片上传失败')));
        }
      }
    }

    Future<void> submit() async {
      final subject = subjectCtrl.text.trim();
      final content = contentCtrl.text.trim();
      if (subject.isEmpty || content.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s['ticketFillAll'] ?? '请填写标题和内容')));
        return;
      }
      isSending.value = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('roxi_token');
        final resp = await AuthService.postWithFallback(
          '/api/tickets',
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'subject': subject,
            'content': content,
            'images': uploadedImages.value,
          }),
        );
        if (resp != null && resp.statusCode == 200) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s['ticketCreated'] ?? '工单已提交，我们会尽快回复！')));
            Navigator.of(context).pop();
          }
        } else {
          final detail = resp != null ? (jsonDecode(utf8.decode(resp.bodyBytes))['detail'] ?? '提交失败') : '网络错误';
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(detail.toString())));
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('错误: $e')));
        }
      }
      isSending.value = false;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Text(s['ticketNew'] ?? '提交工单',
          style: const TextStyle(color: Colors.black87)),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(s['ticketSubject'] ?? '问题标题',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        TextField(
          controller: subjectCtrl, maxLength: 200,
          decoration: InputDecoration(
            hintText: s['ticketSubjectHint'] ?? '简要描述您的问题',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        Text(s['ticketContent'] ?? '问题描述',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        TextField(
          controller: contentCtrl, maxLines: 6, maxLength: 5000,
          decoration: InputDecoration(
            hintText: s['ticketContentHint'] ?? '详细描述您遇到的问题...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 12),
        // Image upload
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (int i = 0; i < uploadedImages.value.length; i++)
            Stack(clipBehavior: Clip.none, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  '${AuthService.baseUrl}${uploadedImages.value[i]}',
                  width: 70, height: 70, fit: BoxFit.cover)),
              Positioned(top: -6, right: -6, child: GestureDetector(
                onTap: () {
                  final list = [...uploadedImages.value];
                  list.removeAt(i);
                  uploadedImages.value = list;
                },
                child: Container(
                  width: 20, height: 20,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 14, color: Colors.white)),
              )),
            ]),
          if (uploadedImages.value.length < 5)
            GestureDetector(
              onTap: pickAndUpload,
              child: Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 24, color: Colors.grey.shade500),
                  Text(s['imgLabel'] ?? '图片', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: isSending.value ? null : submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: isSending.value
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(s['ticketSubmit'] ?? '提交工单'),
          ),
        ),
      ]),
    );
  }
}

/// Upload image to server, returns URL path or null.
Future<String?> _uploadImage(String filePath, String? token) async {
  for (final baseUrl in AuthService.fallbackUrls) {
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/tickets/upload'));
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamed = await req.send().timeout(const Duration(seconds: 15));
      if (streamed.statusCode == 200) {
        final body = await streamed.stream.bytesToString();
        final data = jsonDecode(body);
        return data['url'] as String?;
      }
    } catch (_) {}
  }
  return null;
}
