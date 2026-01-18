import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withOpacity(0.1),
              theme.colorScheme.secondary.withOpacity(0.05),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.settings_rounded,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'الإعدادات',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Settings Content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // General Settings
                    _buildSectionHeader(context, 'عام'),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildSwitchTile(
                            context,
                            'الوضع الليلي',
                            'تفعيل الوضع الليلي',
                            Icons.dark_mode_rounded,
                            settings.darkMode,
                            (value) => settings.setDarkMode(value),
                          ),
                          const Divider(height: 1),
                          _buildSwitchTile(
                            context,
                            'كشف الروابط تلقائياً',
                            'لصق الروابط من الحافظة تلقائياً',
                            Icons.content_paste_rounded,
                            settings.autoDetectLinks,
                            (value) => settings.setAutoDetectLinks(value),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Download Settings
                    _buildSectionHeader(context, 'التحميل'),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildListTile(
                            context,
                            'الجودة الافتراضية',
                            settings.defaultQuality == 'best'
                                ? 'أفضل جودة'
                                : settings.defaultQuality == '720p'
                                    ? '720p'
                                    : settings.defaultQuality == '1080p'
                                        ? '1080p'
                                        : settings.defaultQuality,
                            Icons.high_quality_rounded,
                            () => _showQualityDialog(context, settings),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // About
                    _buildSectionHeader(context, 'حول التطبيق'),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(
                              Icons.info_outline_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            title: const Text('الإصدار'),
                            subtitle: const Text('1.0.0'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Icon(
                              Icons.description_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            title: const Text('دعم المنصات'),
                            subtitle: const Text(
                              'YouTube, Facebook, Instagram, TikTok, Twitter/X, LinkedIn, Vimeo',
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final theme = Theme.of(context);
    return SwitchListTile(
      secondary: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildListTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  void _showQualityDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('اختر الجودة الافتراضية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildQualityOption(
              context,
              'best',
              'أفضل جودة',
              settings.defaultQuality == 'best',
              () {
                settings.setDefaultQuality('best');
                Navigator.of(context).pop();
              },
            ),
            _buildQualityOption(
              context,
              '1080p',
              '1080p - Full HD',
              settings.defaultQuality == '1080p',
              () {
                settings.setDefaultQuality('1080p');
                Navigator.of(context).pop();
              },
            ),
            _buildQualityOption(
              context,
              '720p',
              '720p - HD',
              settings.defaultQuality == '720p',
              () {
                settings.setDefaultQuality('720p');
                Navigator.of(context).pop();
              },
            ),
            _buildQualityOption(
              context,
              '480p',
              '480p - SD',
              settings.defaultQuality == '480p',
              () {
                settings.setDefaultQuality('480p');
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityOption(
    BuildContext context,
    String value,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.1)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: isSelected ? theme.colorScheme.primary : Colors.grey,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? theme.colorScheme.primary : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
