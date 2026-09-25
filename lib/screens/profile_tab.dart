import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../main.dart';
import 'hours_screen.dart';

/// Profile photo, contact details, approval status, and logout — the JSON/
/// mobile equivalent of the top of the website's /cleaner dashboard. The
/// [cleaner] itself is owned by HomeScreen (so the pending-approval banner
/// above the tabs and this screen never disagree); edits call back up via
/// [onCleanerUpdated] instead of holding a separate copy of the truth.
class ProfileTab extends StatefulWidget {
  final Cleaner cleaner;
  final ValueChanged<Cleaner> onCleanerUpdated;
  final Future<void> Function() onLogout;

  const ProfileTab({super.key, required this.cleaner, required this.onCleanerUpdated, required this.onLogout});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _api = ApiClient();
  bool _uploadingPhoto = false;
  bool _loggingOut = false;

  static const _maxPhotoBytes = 4.5 * 1024 * 1024;

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    XFile? picked;
    try {
      picked = await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open camera/library: $e')));
      return;
    }
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (bytes.length > _maxPhotoBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That image is too large — please use one under 4.5MB.')));
      return;
    }
    final ext = picked.path.contains('.') ? picked.path.split('.').last : 'jpg';

    setState(() => _uploadingPhoto = true);
    try {
      final avatarUrl = await _api.uploadPhoto(bytes, ext);
      widget.onCleanerUpdated(Cleaner(
        id: widget.cleaner.id,
        name: widget.cleaner.name,
        email: widget.cleaner.email,
        phone: widget.cleaner.phone,
        address: widget.cleaner.address,
        postcode: widget.cleaner.postcode,
        avatar: avatarUrl,
        status: widget.cleaner.status,
        active: widget.cleaner.active,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _editProfile() async {
    final phoneCtrl = TextEditingController(text: widget.cleaner.phone ?? '');
    final addressCtrl = TextEditingController(text: widget.cleaner.address ?? '');
    final postcodeCtrl = TextEditingController(text: widget.cleaner.postcode ?? '');
    final formKey = GlobalKey<FormState>();

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit your details'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: postcodeCtrl,
                  decoration: const InputDecoration(labelText: 'Postcode'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // Deliberately not disposing phoneCtrl/addressCtrl/postcodeCtrl here — see the
    // matching note in services_tab.dart's _editRate for why: disposing a one-off
    // dialog TextEditingController right after showDialog's Future resolves can
    // race the dialog's still-playing exit animation and crash. They're local
    // variables with no other references after this function returns, so skipping
    // dispose just means normal garbage collection instead.
    final phone = phoneCtrl.text.trim();
    final address = addressCtrl.text.trim();
    final postcode = postcodeCtrl.text.trim();
    if (save != true) return;

    try {
      final updated = await _api.updateProfile(phone: phone, address: address, postcode: postcode);
      widget.onCleanerUpdated(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Details saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _confirmLogout() async {
    setState(() => _loggingOut = true);
    await widget.onLogout(); // navigates away on success; no need to reset _loggingOut
  }

  @override
  Widget build(BuildContext context) {
    final cleaner = widget.cleaner;
    final addressLine = [
      if (cleaner.address?.isNotEmpty == true) cleaner.address! else 'No address on file',
      if (cleaner.postcode?.isNotEmpty == true) cleaner.postcode!,
    ].join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: kBrandLine,
                        backgroundImage: cleaner.avatarUrl != null
                            ? NetworkImage(cleaner.avatarUrl!)
                            : null,
                        child: cleaner.avatarUrl == null
                            ? Text(
                          cleaner.name.isNotEmpty ? cleaner.name[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                        )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _uploadingPhoto ? null : _pickPhoto,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: kBrandPrimary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: _uploadingPhoto
                                ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.edit, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(cleaner.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  if (cleaner.email?.isNotEmpty == true) Text(cleaner.email!, style: TextStyle(color: kBrandMuted)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cleaner.isPendingApproval ? kPendingBg : kSuccessBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      cleaner.isPendingApproval ? '⏳ Pending approval' : '✓ Approved cleaner',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cleaner.isPendingApproval ? kPendingInk : kSuccessInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Contact details', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextButton(onPressed: _editProfile, child: const Text('Edit')),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _InfoRow(icon: Icons.phone, label: cleaner.phone?.isNotEmpty == true ? cleaner.phone! : 'No phone on file'),
                  _InfoRow(icon: Icons.location_on_outlined, label: addressLine),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Working hours'),
              subtitle: const Text('Which days and times you can be booked'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HoursScreen())),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _loggingOut ? null : _confirmLogout,
            icon: _loggingOut
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: kBrandMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: kBrandMuted, fontSize: 13.5))),
        ],
      ),
    );
  }
}