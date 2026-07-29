/// Shoot calendar ("Cuva") models — mirror of /api/team/shoots payloads.

class ShootTeamMember {
  final int id;
  final String name;
  const ShootTeamMember(this.id, this.name);

  factory ShootTeamMember.fromJson(Map<String, dynamic> j) =>
      ShootTeamMember((j['id'] as num).toInt(), j['name'] as String? ?? '?');
}

class ShootAttachment {
  final int id;
  final String kind; // image | file | link
  final String? name;
  final String? mime;
  final int? size;
  final String? url;
  const ShootAttachment({
    required this.id,
    required this.kind,
    this.name,
    this.mime,
    this.size,
    this.url,
  });

  bool get isImage => kind == 'image';
  bool get isLink => kind == 'link';

  factory ShootAttachment.fromJson(Map<String, dynamic> j) => ShootAttachment(
        id: (j['id'] as num).toInt(),
        kind: j['kind'] as String? ?? 'file',
        name: j['name'] as String?,
        mime: j['mime'] as String?,
        size: (j['size'] as num?)?.toInt(),
        url: j['url'] as String?,
      );
}

class Shoot {
  final int id;
  final String title;
  final String type;
  final int? brandId;
  final String? brandName;
  final String? brandColor;
  final String date; // YYYY-MM-DD
  final String? startTime; // HH:mm
  final String? endTime;
  final String? location;
  final String? location2;
  final String? locationLabel;
  final String? notes;
  final String status;
  final int? leadId;
  final List<ShootTeamMember> team;
  final List<ShootAttachment> attachments;

  const Shoot({
    required this.id,
    required this.title,
    required this.type,
    required this.brandId,
    required this.brandName,
    required this.brandColor,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.location2,
    required this.locationLabel,
    required this.notes,
    required this.status,
    required this.leadId,
    required this.team,
    this.attachments = const [],
  });

  bool get isCancelled => status == 'cancelled';

  factory Shoot.fromJson(Map<String, dynamic> j) {
    final brand = j['brand'] as Map<String, dynamic>?;
    return Shoot(
      id: (j['id'] as num).toInt(),
      title: j['title'] as String? ?? 'Shoot',
      type: j['type'] as String? ?? 'lifestyle',
      brandId: brand != null ? (brand['id'] as num?)?.toInt() : null,
      brandName: brand?['name'] as String?,
      brandColor: brand?['color'] as String?,
      date: j['date'] as String? ?? '',
      startTime: j['start_time'] as String?,
      endTime: j['end_time'] as String?,
      location: j['location'] as String?,
      location2: j['location_2'] as String?,
      locationLabel: j['location_label'] as String?,
      notes: j['notes'] as String?,
      status: j['status'] as String? ?? 'scheduled',
      leadId: (j['lead_id'] as num?)?.toInt(),
      team: ((j['team'] ?? []) as List)
          .map((e) => ShootTeamMember.fromJson(e as Map<String, dynamic>))
          .toList(),
      attachments: ((j['attachments'] ?? []) as List)
          .map((e) => ShootAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Options for the "Add to Cuva" form.
class ShootFormOptions {
  final List<ShootBrandOption> brands;
  final List<ShootTeamOption> team;
  final List<String> types;
  const ShootFormOptions(this.brands, this.team, this.types);

  factory ShootFormOptions.fromJson(Map<String, dynamic> j) => ShootFormOptions(
        ((j['brands'] ?? []) as List)
            .map((e) => ShootBrandOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        ((j['team'] ?? []) as List)
            .map((e) => ShootTeamOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        ((j['types'] ?? []) as List).map((e) => e.toString()).toList(),
      );
}

class ShootBrandOption {
  final int id;
  final String name;
  final String? color;
  const ShootBrandOption(this.id, this.name, this.color);
  factory ShootBrandOption.fromJson(Map<String, dynamic> j) =>
      ShootBrandOption((j['id'] as num).toInt(), j['name'] as String? ?? '?', j['color'] as String?);
}

class ShootTeamOption {
  final int id;
  final String name;
  final String? jobTitle;
  final String? avatarColor;
  const ShootTeamOption(this.id, this.name, this.jobTitle, this.avatarColor);
  factory ShootTeamOption.fromJson(Map<String, dynamic> j) => ShootTeamOption(
        (j['id'] as num).toInt(),
        j['name'] as String? ?? '?',
        j['job_title'] as String?,
        j['avatar_color'] as String?,
      );
}
