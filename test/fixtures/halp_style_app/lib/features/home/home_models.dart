class HomeCard {
  const HomeCard({required this.title});

  factory HomeCard.fromMap(Map<String, dynamic> map) => HomeCard(title: map['title'] as String);

  final String title;

  Map<String, dynamic> toMap() => {'title': title};
}
