import 'package:flutter/material.dart';
import '../main.dart';
import '../services/auth_service.dart';
import 'onboarding_screen.dart';
import 'profile_setup_screen.dart';

class OtpScreen extends StatefulWidget {
  final String email, role;
  const OtpScreen({super.key, required this.email, this.role = 'CUSTOMER'});
  @override State<OtpScreen> createState() => _OtpScreenState();
}
class _OtpScreenState extends State<OtpScreen> {
  final code=TextEditingController(); bool busy=false;
  Future<void> verify() async {
    if(code.text.trim().length!=6){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter the 6-digit code.')));return;}
    setState(()=>busy=true);
    try {
      final result=await AuthService.verify(widget.email,code.text.trim());
      await AuthService.saveSession(result); if(!mounted)return;
      Navigator.pushAndRemoveUntil(context,PageRouteBuilder(pageBuilder:(_,a,b)=>ProfileSetupScreen(name:result['user']['name'],role:result['user']['role']),transitionsBuilder:(_,a,b,child)=>SlideTransition(position:Tween<Offset>(begin:const Offset(.12,0),end:Offset.zero).animate(CurvedAnimation(parent:a,curve:Curves.easeOutCubic)),child:FadeTransition(opacity:a,child:child)),transitionDuration:const Duration(milliseconds:360)),(_)=>false);
    } catch(e) {if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ','')),backgroundColor:red));}
    finally {if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(body:Stack(children:[const Positioned.fill(child:CinematicBackdrop()),SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(24,10,24,24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.arrow_back)),const SizedBox(height:22),Container(width:55,height:55,decoration:BoxDecoration(color:red.withOpacity(.15),borderRadius:BorderRadius.circular(17)),child:const Icon(Icons.mark_email_read_outlined,color:red,size:28)),const SizedBox(height:22),const Text('Check your inbox.',style:TextStyle(fontSize:30,fontWeight:FontWeight.w800)),const SizedBox(height:9),Text('Enter the 6-digit code sent to ${widget.email}.',style:const TextStyle(color:muted,height:1.5)),const SizedBox(height:25),TextField(controller:code,maxLength:6,keyboardType:TextInputType.number,textAlign:TextAlign.center,style:const TextStyle(fontSize:25,letterSpacing:12,fontWeight:FontWeight.w700),decoration:const InputDecoration(counterText:'',hintText:'••••••',hintStyle:TextStyle(color:Colors.white24,letterSpacing:10))),const SizedBox(height:17),SizedBox(width:double.infinity,height:54,child:FilledButton(onPressed:busy?null:verify,style:FilledButton.styleFrom(backgroundColor:red,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16))),child:busy?const CircularProgressIndicator(color:Colors.white):const Text('Verify email',style:TextStyle(fontWeight:FontWeight.w700)))),Center(child:TextButton(onPressed:()async{try{await AuthService.resend(widget.email);if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('A new code has been sent.')));}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}},child:const Text('Resend code',style:TextStyle(color:red)))),const Spacer(),const Text('Email verification protects your DriveMate account.',style:TextStyle(color:muted,fontSize:12))])))]));
}
