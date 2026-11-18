class Note {
  Note({required this.id});

  factory Note.fromJson(Map<String, dynamic> json) => Note(id: json['id'] as int);

  final int id;

  Map<String, dynamic> toJson() => {'id': id};
}
