import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/app_bottom_bar.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Home"),
      ),
      drawer: const AppNavDrawer(),
      body: const Center(child: Text("Main Home Content Area")),
      bottomNavigationBar: const AppBottomBar(),
    );
  }
}
