import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: CounterPage()));

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});
  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _n = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () {
      setState(() => _n++);
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
    },
    child: Text('$_n'),
  );
}
