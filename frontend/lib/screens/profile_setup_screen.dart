import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../main.dart';
import '../services/auth_service.dart';
import 'driver_documents_screen.dart';
import 'home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String name, role;
  const ProfileSetupScreen({super.key, required this.name, required this.role});
  @override State<ProfileSetupScreen> createState()=>_ProfileSetupScreenState();
}
class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final form=GlobalKey<FormState>(); final picker=ImagePicker();
  final address=TextEditingController(),city=TextEditingController(),emergencyName=TextEditingController(),emergencyPhone=TextEditingController(),languages=TextEditingController(),intro=TextEditingController(),licence=TextEditingController(),experience=TextEditingController();
  final skills=<String,bool>{'manual_transmission':false,'automatic_transmission':false,'sedan':false,'suv':false,'luxury':false,'highway':false,'night_driving':false,'outstation':false};
  XFile? photo; DateTime? dob,licenceExpiry; int step=0; bool saving=false;
  bool get driver=>widget.role=='DRIVER';
  @override void dispose(){address.dispose();city.dispose();emergencyName.dispose();emergencyPhone.dispose();languages.dispose();intro.dispose();licence.dispose();experience.dispose();super.dispose();}
  bool get adult {if(dob==null)return false;final n=DateTime.now();var age=n.year-dob!.year;if(n.month<dob!.month||(n.month==dob!.month&&n.day<dob!.day))age--;return age>=18;}
  Future<void> pickPhoto() async {final f=await picker.pickImage(source:ImageSource.gallery,maxWidth:1400,imageQuality:82);if(f!=null)setState(()=>photo=f);}
  Future<void> pickDate({required bool birth}) async {final now=DateTime.now();final selected=await showDatePicker(context:context,initialDate:birth?(dob??DateTime(now.year-25,1,1)):(licenceExpiry??now.add(const Duration(days:365))),firstDate:birth?DateTime(1930):now,lastDate:birth?DateTime(now.year-16):DateTime(now.year+30),builder:(c,child)=>Theme(data:ThemeData.dark().copyWith(colorScheme:const ColorScheme.dark(primary:red,surface:panel)),child:child!));if(selected!=null)setState(()=>birth?dob=selected:licenceExpiry=selected);}
  String iso(DateTime? d)=>d==null?'':'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  Future<void> save() async {
    if(!form.currentState!.validate())return;
    if(photo==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Please add a profile photo to continue.')));return;}
    if(driver&&step==0){if(!adult){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Driver applicants must be 18 or older.')));return;}setState(()=>step=1);return;}
    if(driver&&!adult){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Driver applicants must be 18 or older.')));return;}
    if(driver&&(licenceExpiry==null||licence.text.trim().isEmpty)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter licence number and expiry date.')));return;}
    if(driver&&!skills.values.any((value)=>value)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Select at least one driving capability.')));return;}
    setState(()=>saving=true);
    try {
      await AuthService.uploadPrivateFile('profile/photo/',photo!.path);
      final data=<String,dynamic>{'address':address.text.trim(),'city':city.text.trim(),'emergency_contact_name':emergencyName.text.trim(),'emergency_contact_phone':emergencyPhone.text.trim()};
      if(driver)data.addAll({'date_of_birth':iso(dob),'languages':languages.text.trim(),'introduction':intro.text.trim(),'licence_number':licence.text.trim(),'licence_expiry':iso(licenceExpiry),'experience_years':int.parse(experience.text),...skills});
      await AuthService.saveProfile(data);if(!mounted)return;
      if(driver){Navigator.pushReplacement(context,_animatedRoute(DriverDocumentsScreen(name:widget.name)));}
      else{Navigator.pushAndRemoveUntil(context,_animatedRoute(HomeScreen(role:'Customer',name:widget.name)),(_)=>false);}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ','')),backgroundColor:red));}
    finally{if(mounted)setState(()=>saving=false);}
  }
  PageRoute<T> _animatedRoute<T>(Widget page)=>PageRouteBuilder<T>(pageBuilder:(_,a,b)=>page,transitionsBuilder:(_,a,b,child)=>SlideTransition(position:Tween<Offset>(begin:const Offset(.08,0),end:Offset.zero).animate(CurvedAnimation(parent:a,curve:Curves.easeOutCubic)),child:FadeTransition(opacity:a,child:child)),transitionDuration:const Duration(milliseconds:350));
  String? requiredText(String? value,String label)=>value==null||value.trim().isEmpty?'$label is required':null;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => step == 1 && driver ? setState(() => step = 0) : Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
        title: Text(driver ? 'Driver application' : 'Rider profile', style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Form(
        key: form,
        child: ListView(padding: const EdgeInsets.fromLTRB(22, 8, 22, 30), children: [
          _progress(),
          Text(driver ? (step == 0 ? 'Personal details' : 'Driving details') : 'Your profile', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(driver ? 'All fields are required before continuing. Drivers must be at least 18.' : 'Complete your required profile details.', style: const TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 18),
          Center(child: GestureDetector(onTap: pickPhoto, child: Stack(children: [
            CircleAvatar(radius: 48, backgroundColor: panel, backgroundImage: photo == null ? null : FileImage(File(photo!.path)), child: photo == null ? const Icon(Icons.add_a_photo_outlined, color: red, size: 27) : null),
            Positioned(right: 0, bottom: 0, child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: red, shape: BoxShape.circle), child: const Icon(Icons.edit, size: 14, color: Colors.white))),
          ]))),
          const SizedBox(height: 7),
          const Center(child: Text('Required profile photo', style: TextStyle(color: muted, fontSize: 11))),
          const SizedBox(height: 18),
          AnimatedSwitcher(duration: const Duration(milliseconds: 280), transitionBuilder: (child, a) => SlideTransition(position: Tween<Offset>(begin: const Offset(.04, 0), end: Offset.zero).animate(a), child: FadeTransition(opacity: a, child: child)), child: Column(key: ValueKey('$driver-$step'), children: [if (!driver || step == 0) ..._personalFields(), if (driver && step == 1) ..._drivingFields()])),
          const SizedBox(height: 20),
          SizedBox(height: 53, child: FilledButton(onPressed: saving ? null : save, style: FilledButton.styleFrom(backgroundColor: red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: saving ? const CircularProgressIndicator(color: Colors.white) : Text(driver && step == 0 ? 'Continue' : 'Save and continue', style: const TextStyle(fontWeight: FontWeight.w700)))),
          if (driver && step == 1) const Padding(padding: EdgeInsets.only(top: 12), child: Text('After these details, submit your licence and identity proof for secure admin review. Your driver account stays offline until approved.', style: TextStyle(color: muted, fontSize: 11, height: 1.45))),
        ]),
      ),
    );
  }

  Widget _progress() => Padding(padding: const EdgeInsets.only(bottom: 22), child: Row(children: [
    Expanded(child: Container(height: 4, decoration: BoxDecoration(color: red, borderRadius: BorderRadius.circular(4)))),
    if (driver) ...[const SizedBox(width: 7), Expanded(child: Container(height: 4, decoration: BoxDecoration(color: step == 1 ? red : Colors.white12, borderRadius: BorderRadius.circular(4))))],
  ]));
  List<Widget> _personalFields()=>[
    if(driver)...[_dateTile('Date of birth',dob,birth:true),if(dob!=null&&!adult)const Padding(padding:EdgeInsets.only(top:7,bottom:8),child:Text('You must be 18 or older to register as a driver.',style:TextStyle(color:Color(0xFFFF6B6B),fontSize:12))),const SizedBox(height:13)],
    TextFormField(controller:address,decoration:const InputDecoration(labelText:'Current address',prefixIcon:Icon(Icons.location_on_outlined)),validator:(v)=>requiredText(v,'Address')),const SizedBox(height:13),
    TextFormField(controller:city,decoration:const InputDecoration(labelText:'City / service area',prefixIcon:Icon(Icons.location_city_outlined)),validator:(v)=>requiredText(v,'City')),const SizedBox(height:13),
    TextFormField(controller:emergencyName,decoration:const InputDecoration(labelText:'Emergency contact name',prefixIcon:Icon(Icons.contact_emergency_outlined)),validator:(v)=>requiredText(v,'Emergency contact name')),const SizedBox(height:13),
    TextFormField(controller:emergencyPhone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Emergency contact phone',prefixIcon:Icon(Icons.phone_outlined)),validator:(v)=>v==null||v.trim().length<8?'Enter a valid emergency phone':null),
  ];
  List<Widget> _drivingFields()=>[
    TextFormField(controller:licence,decoration:const InputDecoration(labelText:'Driving licence number',prefixIcon:Icon(Icons.badge_outlined)),validator:(v)=>requiredText(v,'Licence number')),const SizedBox(height:13),
    _dateTile('Licence expiry date',licenceExpiry,birth:false),const SizedBox(height:13),
    TextFormField(controller:experience,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Driving experience (years)',prefixIcon:Icon(Icons.timelapse_outlined)),validator:(v)=>v==null||int.tryParse(v)==null||int.parse(v)<0?'Enter experience in years':null),const SizedBox(height:13),
    TextFormField(controller:languages,decoration:const InputDecoration(labelText:'Languages known',prefixIcon:Icon(Icons.language)),validator:(v)=>requiredText(v,'Languages')),const SizedBox(height:13),
    TextFormField(controller:intro,maxLines:3,maxLength:400,decoration:const InputDecoration(labelText:'Short introduction',alignLabelWithHint:true),validator:(v)=>requiredText(v,'Introduction')),const SizedBox(height:8),
    const Align(alignment:Alignment.centerLeft,child:Text('Select your driving capabilities',style:TextStyle(fontWeight:FontWeight.w700,fontSize:14))),const SizedBox(height:7),
    Wrap(spacing:7,runSpacing:1,children:skills.keys.map((key){final label={'manual_transmission':'Manual','automatic_transmission':'Automatic','sedan':'Sedan','suv':'SUV','luxury':'Luxury','highway':'Highway','night_driving':'Night driving','outstation':'Outstation'}[key]!;return FilterChip(label:Text(label),selected:skills[key]!,onSelected:(v)=>setState(()=>skills[key]=v),selectedColor:red.withOpacity(.2),checkmarkColor:red,backgroundColor:panel,side:const BorderSide(color:Colors.white12));}).toList()),
  ];
  Widget _dateTile(String label,DateTime? value,{required bool birth})=>InkWell(onTap:()=>pickDate(birth:birth),child:InputDecorator(decoration:InputDecoration(labelText:label,prefixIcon:const Icon(Icons.calendar_month_outlined),suffixIcon:const Icon(Icons.edit_calendar_outlined)),child:Text(value==null?'Select date':'${value.day.toString().padLeft(2,'0')}/${value.month.toString().padLeft(2,'0')}/${value.year}',style:TextStyle(color:value==null?muted:softWhite))));
}
