import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import '../widgets/brand_mark.dart';
import 'onboarding_screen.dart';
class SplashScreen extends StatefulWidget {const SplashScreen({super.key});@override State<SplashScreen> createState()=>_SplashScreenState();}
class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {late final AnimationController c;late final Animation<double> fade;@override void initState(){super.initState();c=AnimationController(vsync:this,duration:const Duration(milliseconds:900))..forward();fade=CurvedAnimation(parent:c,curve:Curves.easeOut);Timer(const Duration(milliseconds:1900),(){if(mounted)Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const OnboardingScreen()));});}@override void dispose(){c.dispose();super.dispose();}@override Widget build(BuildContext context)=>Scaffold(backgroundColor:navy,body:Center(child:FadeTransition(opacity:fade,child:Column(mainAxisSize:MainAxisSize.min,children:[const BrandMark(size:92),const SizedBox(height:22),Text('DriveMate',style:Theme.of(context).textTheme.headlineMedium?.copyWith(color:Colors.white,fontWeight:FontWeight.w800,letterSpacing:-.8)),const SizedBox(height:7),Text('Your car. Your destination. Your driver.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white.withOpacity(.72),fontSize:13))]))));}
