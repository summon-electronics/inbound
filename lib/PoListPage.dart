// // lib/PoListPage.dart
// import 'package:flutter/material.dart';
// import 'package:inboundgenie/PoItemDetailsPage.dart';
//
// class PoItem {
//   final String poNumber;
//   final DateTime date;
//   final int amount;
//
//   PoItem({
//     required this.poNumber,
//     required this.date,
//     required this.amount,
//   });
// }
//
// class PoListPage extends StatefulWidget {
//   const PoListPage({Key? key}) : super(key: key);
//
//   @override
//   State<PoListPage> createState() => _PoListPageState();
// }
//
// class _PoListPageState extends State<PoListPage> {
//   final List<PoItem> _poItems = [
//     PoItem(poNumber: 'PO-02530', date: DateTime(2024, 2, 29), amount: 1500),
//     PoItem(poNumber: 'PO-03721', date: DateTime(2024, 3, 15), amount: 2750),
//     PoItem(poNumber: 'PO-04892', date: DateTime(2024, 4, 2), amount: 3200),
//   ];
//
//   String? _selectedPoNumber; // Stores selected PO number
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text(
//           'Select PO Number',
//           style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
//         ),
//         backgroundColor: const Color(0xFF0070C0),
//         iconTheme: const IconThemeData(color: Colors.white),
//         centerTitle: true,
//       ),
//       body: Column(
//         children: [
//           // 🌟 PO list with radio buttons
//           Expanded(
//             child: ListView.builder(
//               padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
//               itemCount: _poItems.length,
//               itemBuilder: (context, idx) {
//                 final item = _poItems[idx];
//                 return Padding(
//                   padding: const EdgeInsets.only(bottom: 12),
//                   child: Card(
//                     color: Colors.white,
//                     elevation: 2,
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                     child: RadioListTile<String>(
//                       value: item.poNumber,
//                       groupValue: _selectedPoNumber,
//                       onChanged: (value) {
//                         setState(() {
//                           _selectedPoNumber = value;
//                         });
//                       },
//                       activeColor: const Color(0xFF0070C0),
//                       title: Text(
//                         item.poNumber,
//                         style: const TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.bold,
//                           color: Color(0xFF003366),
//                         ),
//                       ),
//                       subtitle: Text(
//                         _formatDate(item.date),
//                         style: const TextStyle(
//                           fontSize: 14,
//                           color: Color(0xFF005A9E),
//                         ),
//                       ),
//                       secondary: Container(
//                         padding: const EdgeInsets.symmetric(
//                             horizontal: 12, vertical: 6),
//                         decoration: BoxDecoration(
//                           color: const Color(0xFF0070C0),
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                         child: Text(
//                           item.amount.toString(),
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                       ),
//                     ),
//                   ),
//                 );
//               },
//             ),
//           ),
//
//           // 🌟 NEXT button pinned at bottom
//           SafeArea(
//             minimum: const EdgeInsets.all(16),
//             child: SizedBox(
//               width: double.infinity,
//               height: 48,
//               child: ElevatedButton(
//                 onPressed: _onNextPressed,
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: const Color(0xFF0070C0),
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(24),
//                   ),
//                   textStyle: const TextStyle(
//                       fontSize: 16, fontWeight: FontWeight.bold),
//                 ),
//                 child: const Text(
//                   'NEXT',
//                   style: TextStyle(
//                     fontSize: 16,
//                     fontWeight: FontWeight.bold,
//                     color: Colors.white,
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   String _formatDate(DateTime d) {
//     final y = d.year.toString().padLeft(4, '0');
//     final m = d.month.toString().padLeft(2, '0');
//     final day = d.day.toString().padLeft(2, '0');
//     return '$y-$m-$day';
//   }
//
//   void _onNextPressed() {
//     if (_selectedPoNumber == null) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Please select a PO number.')),
//       );
//       return;
//     }
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (_) => PoItemDetailsPage(itemName: '',),
//       ),
//     );
//   }
// }
