import SwiftUI

struct ExamQuestion {
 let prompt: String
 let choices: [String]
 let correct: Int
 let explanation: String
 let law: String
}
let questions: [ExamQuestion] = [
 .init(prompt:"A psychologist has reasonable cause to suspect child abuse. When should a report be made?",choices:["At the next renewal","Within 30 days","Immediately","Only after a court order"],correct:2,explanation:"A report must be made immediately when child abuse is known or reasonably suspected. Conclusive proof is not required.",law:"F.S. 39.201"),
 .init(prompt:"Who may claim psychotherapist-patient privilege on a patient's behalf?",choices:["The patient's financial planner","The patient's guardian or conservator","The patient's landlord","The patient's coworker"],correct:1,explanation:"A guardian or conservator may claim the privilege under the statutory conditions. A financial planner cannot claim it merely by holding that role.",law:"F.S. 90.503"),
 .init(prompt:"Which conduct is consistent with Florida psychology licensing exemptions for supervised trainees?",choices:["Claiming to be a licensed psychologist","Performing any private practice","Disclosing their status as a trainee","Working without supervision"],correct:2,explanation:"Qualifying students or trainees must clearly identify their supervised training status and meet the exemption's conditions.",law:"F.S. 490.014"),
 .init(prompt:"When must a suspected case of exploitation of a vulnerable adult be reported?",choices:["Immediately","After a criminal conviction","At license renewal","Only if the patient agrees"],correct:0,explanation:"Knowledge or reasonable suspicion of abuse, neglect or exploitation triggers an immediate reporting obligation.",law:"F.S. 415.1034"),
 .init(prompt:"What is the usual minimum passing score for the 40 scored items on the Florida Psychology Laws and Rules exam?",choices:["20","28","32","40"],correct:2,explanation:"The published passing standard is 32 out of 40 scored questions (80%).",law:"Pearson VUE Candidate Information Booklet"),
 .init(prompt:"A clinician suspects a patient is at risk but wishes to apply the Baker Act. What is required?",choices:["Diagnosis alone","Qualifying statutory examination criteria","Family preference alone","Lack of insurance"],correct:1,explanation:"Involuntary examination requires the relevant refusal or inability conditions and statutory risk or neglect criteria.",law:"F.S. 394.463"),
 .init(prompt:"What does the use of the word SHALL in a statutory obligation generally indicate?",choices:["An optional action","An exemption","A mandatory duty","An informal suggestion"],correct:2,explanation:"In statutory language, shall generally establishes a required action rather than discretionary permission.",law:"Florida statutory interpretation")
]
struct ContentView: View {
 @State private var stage = 0
 @State private var tutorial = 0
 @State private var idx = 0
 @State private var responses: [Int:Int] = [:]
 @State private var flags: Set<Int> = []
 @State private var scratch = ""
 @State private var showScratch = false
 @State private var showInfo = false
 @State private var showSubmit = false
 @State private var start = Date()
 @State private var remaining = 3600
 private let blue = Color(red:0,green:0.42,blue:0.65)
 private let pale = Color(red:0.55,green:0.72,blue:0.87)
 let tutorialPages = ["Welcome to the Practice Exam Tutorial","Scratch Pad","Flag for Review","Navigator and Section Review","End of Tutorial"]
 var body: some View {
  VStack(spacing:0) {
   HStack { Text(stage == 0 ? "Tutorial - Candidate" : "Florida Laws & Rules Exam - Candidate").font(.system(size:12,weight:.semibold)); Spacer(); VStack(alignment:.trailing){Text("Time Remaining " + String(format:"%02d:%02d",remaining/60,remaining%60));Text(stage == 0 ? "\(tutorial+1) of 5" : stage == 1 ? "\(idx+1) of \(questions.count)" : "Section Review")}.font(.system(size:10)) }.foregroundStyle(.white).padding(12).background(blue)
   HStack { Button("Scratch Pad"){showScratch=true}; Button("Exam Info"){showInfo=true}; Spacer(); if stage == 1 { Button(flags.contains(idx) ? "⚑ Flagged":"⚐ Flag for Review"){ if flags.contains(idx){flags.remove(idx)}else{flags.insert(idx)} } } }.font(.system(size:11)).tint(.white).padding(10).background(pale)
   ScrollView {
    VStack(alignment:.leading,spacing:19) {
     if stage == 0 {
      Text(tutorialPages[tutorial]).font(.headline).frame(maxWidth:.infinity)
      Text(["Welcome. Use Next to learn exam controls.","The Scratch Pad stores personal notes.","Flag for Review marks a question without changing your answer.","The Navigator lets you return to answered, incomplete and flagged items.","Full practice exam: 45 items, 40 scored, 5 unscored, 60 minutes. This build is a seven-question interface pilot."][tutorial])
     } else if stage == 1 {
      Text(questions[idx].prompt).font(.system(size:16))
      ForEach(0..<4,id:\.self){ i in
       Button {responses[idx]=i} label:{
        HStack(alignment:.top,spacing:9) {
         Image(systemName:responses[idx]==i ? "largecircle.fill.circle":"circle")
         Text(questions[idx].choices[i]).multilineTextAlignment(.leading)
         Spacer(minLength:0)
        }.foregroundStyle(.black).padding(.vertical,8)
       }
      }
     } else if stage == 2 {
      Text("Section Review").font(.headline).frame(maxWidth:.infinity)
      Text("\(questions.count-responses.count) incomplete · \(flags.count) flagged")
      LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())]) {
       ForEach(questions.indices,id:\.self){ i in
        Button("Question \(i+1) \(flags.contains(i) ? "⚑":"") \(responses[i] == nil ? "○":"✓")") {idx=i;stage=1}.font(.system(size:12)).padding(12).frame(maxWidth:.infinity).background(Color.gray.opacity(0.12))
       }
      }
     } else {
      let score=questions.indices.filter{responses[$0]==questions[$0].correct}.count
      Text("Examination Score Report").font(.headline).frame(maxWidth:.infinity)
      Text("\(score) / \(questions.count) correct").font(.title2).bold()
      Text("Interface pilot only — not the official 40-item scored examination.")
      ForEach(questions.indices,id:\.self){ i in
       VStack(alignment:.leading,spacing:6){
        Text("Question \(i+1) — \(responses[i]==questions[i].correct ? "Correct":"Incorrect")").bold()
        Text(questions[i].prompt)
        Text("Correct answer: \(questions[i].choices[questions[i].correct])").bold()
        Text(questions[i].explanation)
        Text(questions[i].law).font(.caption).foregroundStyle(.secondary)
       }.padding(.vertical,12)
      }
     }
    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
   }
   HStack {
    if stage == 0 {
     Button("◀ Previous"){tutorial=max(0,tutorial-1)}.disabled(tutorial==0)
     Spacer()
     Button(tutorial==4 ? "Begin Exam ▶":"Next ▶"){ if tutorial<4{tutorial+=1}else{stage=1;start=Date();remaining=3600}}
    } else if stage == 1 {
     Button("◀ Previous"){idx=max(0,idx-1)}.disabled(idx==0)
     Spacer()
     Button("Navigator"){stage=2}
     Spacer()
     Button(idx==questions.count-1 ? "Review ▶":"Next ▶"){if idx==questions.count-1{stage=2}else{idx+=1}}
    } else if stage == 2 {
     Button("Return to Exam"){stage=1}
     Spacer()
     Button("End Review"){showSubmit=true}
    } else {
     Button("New Exam"){stage=0;tutorial=0;idx=0;responses=[:];flags=[];remaining=3600}
    }
   }.font(.system(size:12,weight:.semibold)).tint(.white).padding(13).background(blue)
  }
  .font(.system(size:14))
  .background(.white)
  .sheet(isPresented:$showScratch){NavigationStack{VStack{TextEditor(text:$scratch).padding();Spacer()}.navigationTitle("Scratch Pad").toolbar{Button("Done"){showScratch=false}}}}
  .alert("Exam Information",isPresented:$showInfo){Button("OK",role:.cancel){}} message:{Text("Native SwiftUI interface pilot. The complete 325-question bank remains in the previously prepared project archive.")}
  .alert("Submit Exam?",isPresented:$showSubmit){Button("Cancel",role:.cancel){};Button("Submit"){stage=3}}message:{Text("Unanswered questions will be marked incorrect.")}
  .onReceive(Timer.publish(every:1,on:.main,in:.common).autoconnect()){ _ in if stage==1 || stage==2 {remaining=max(0,3600-Int(Date().timeIntervalSince(start)));if remaining==0{stage=3}}}
 }
}
@main struct PsychologyLawNativeApp: App {var body:some Scene {WindowGroup{ContentView().preferredColorScheme(.light)}}}
