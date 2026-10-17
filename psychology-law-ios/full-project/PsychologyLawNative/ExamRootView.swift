import SwiftUI

enum SimulatorPanel: Equatable {
    case examInfo
    case help
    case navigator
    case submit

    var title: String {
        switch self {
        case .examInfo: return "Exam Information"
        case .help: return "Help"
        case .navigator: return "Navigator"
        case .submit: return "End Exam"
        }
    }
}

struct ExamRootView: View {
    @StateObject private var store = ExamStore()
    @State private var panel: SimulatorPanel?
    @Environment(\.scenePhase) private var scenePhase

    private var stage: ExamStage { store.snapshot.stage }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    toolbar
                    Group {
                        switch stage {
                        case .tutorial: tutorialContent
                        case .exam: examContent
                        case .review: reviewContent(width: geometry.size.width)
                        case .results: resultsContent
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    footer
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let panel {
                    panelOverlay(panel, width: geometry.size.width, height: geometry.size.height)
                }
                if let error = store.errorText {
                    errorOverlay(error)
                }
            }
            .foregroundColor(PearsonStyle.text)
        }
        .onChange(of: scenePhase) { nextPhase in
            switch nextPhase {
            case .background:
                // Treat leaving the app as ending the current examination.
                panel = nil
                store.resetForExit()
            case .active:
                store.refreshClock()
            default:
                break
            }
        }
        .onChange(of: stage) { next in
            if next == .results { panel = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Florida Laws & Rules Examination Simulator")
                    .font(.system(size: 16.5, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.92)
                    .fixedSize(horizontal: false, vertical: true)
                Text(store.displayName.uppercased())
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text("Time Remaining").font(.system(size: 12, weight: .medium))
                Text(stage == .results ? "--:--" : store.clockText)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                Text(counterLabel).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundColor(.white)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: 104)
        .background(PearsonStyle.blue)
        .accessibilityElement(children: .combine)
    }

    private var counterLabel: String {
        switch stage {
        case .tutorial: return "▣ \(min(store.snapshot.tutorialIndex + 1, 4)) of 4"
        case .exam: return "▣ \(store.snapshot.currentIndex + 1) of \(store.questionCount)"
        case .review: return "▣ Section Review"
        case .results: return "▣ Score Report"
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button { panel = .examInfo } label: { Text("Exam Info") }
            Spacer(minLength: 4)
            if stage == .exam {
                Button { store.toggleFlag() } label: {
                    Label(store.currentItem?.isFlagged == true ? "Flagged" : "Flag for Review",
                          systemImage: store.currentItem?.isFlagged == true ? "flag.fill" : "flag")
                }
                .accessibilityIdentifier("flagButton")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(PearsonStyle.toolbar)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0) {
            switch stage {
            case .tutorial:
                HStack(spacing: 0) {
                    PearsonFooterButton(title: "ⓘ Exam Info") { panel = .examInfo }
                    Spacer(minLength: 0)
                    PearsonFooterButton(title: "◀ Previous", disabled: store.snapshot.tutorialIndex == 0) {
                        store.previousTutorial()
                    }
                    PearsonFooterButton(title: store.snapshot.tutorialIndex >= 3 ? "Begin Exam ▶" : "Next ▶") {
                        store.nextTutorial()
                    }
                }
            case .exam:
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        PearsonFooterButton(title: "Help") { panel = .help }
                            .frame(maxWidth: .infinity)
                        PearsonFooterButton(title: "Navigator") { panel = .navigator }
                            .frame(maxWidth: .infinity)
                        PearsonFooterButton(title: "End Exam") { panel = .submit }
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("endExamButton")
                    }
                    Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1)
                    HStack(spacing: 0) {
                        PearsonFooterButton(title: "◀ Previous", disabled: store.snapshot.currentIndex == 0) {
                            store.previousQuestion()
                        }
                        .frame(maxWidth: .infinity)
                        PearsonFooterButton(title: store.snapshot.currentIndex == store.questionCount - 1 ? "Review ▶" : "Next ▶") {
                            store.nextQuestion()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            case .review:
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        PearsonFooterButton(title: "Return to Exam") { store.returnToExam() }
                        Spacer(minLength: 0)
                        PearsonFooterButton(title: "End Exam") { panel = .submit }
                    }
                    Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1)
                    HStack(spacing: 0) {
                        PearsonFooterButton(title: "Review All") { store.selectReviewFilter(.all) }
                        Spacer(minLength: 0)
                        PearsonFooterButton(title: "Review Incomplete") { store.selectReviewFilter(.incomplete) }
                        Spacer(minLength: 0)
                        PearsonFooterButton(title: "Review Flagged") { store.selectReviewFilter(.flagged) }
                    }
                }
            case .results:
                HStack(spacing: 0) {
                    PearsonFooterButton(title: "Start New Exam") { store.restart() }
                    Spacer(minLength: 0)
                    PearsonFooterButton(title: store.snapshot.showAllAnswers ? "Incorrect Only" : "Review All") {
                        store.toggleResultReview()
                    }
                }
            }
        }
        .background(PearsonStyle.blue)
    }

    private let tutorialHeadings = [
        "Welcome to the Practice Exam Tutorial", "Flag for Review",
        "Navigator and Section Review", "End of Tutorial"
    ]

    private var tutorialContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                let step = min(max(0, store.snapshot.tutorialIndex), 3)
                Text(tutorialHeadings[step])
                    .font(.system(size: PearsonStyle.textSize(15), weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                switch step {
                case 0:
                    Text("This tutorial demonstrates how the practice examination screen works. Follow the instructions before beginning your timed practice exam.")
                    Text("Candidate Name").fontWeight(.bold)
                    TextField("Enter candidate name", text: Binding(
                        get: { store.snapshot.candidateName },
                        set: { store.setCandidateName($0) }
                    ))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(11)
                    .overlay(Rectangle().stroke(PearsonStyle.line))
                    .accessibilityIdentifier("candidateNameField")
                    Text("Use the Previous and Next buttons at the bottom of the screen to navigate the tutorial.")
                case 1:
                    Text("Select Flag for Review to mark the current question for later review. A flag does not change your selected answer.")
                    Text("You can return to flagged questions at any point before submitting the examination.")
                case 2:
                    Text("Navigator shows the question numbers and indicates answered and flagged questions.")
                    Text("Section Review allows you to select Review All, Review Incomplete or Review Flagged. End Exam presents a confirmation before scoring.")
                default:
                    Text("This is the end of the practice-exam tutorial.")
                    Text("The exam has 45 questions, with 40 scored questions and 5 unscored practice questions.")
                    Text("You have 60 minutes to complete the exam. A score of at least 32 correct answers among the 40 scored questions is required for PASS.")
                    Text("Use Previous, Next, Flag for Review, and Navigator to move through the exam. Select End Exam in the footer to finish early, then confirm your choice.")
                    Text("Select Begin Exam at the bottom right when you are ready.")
                }
                Spacer(minLength: 20)
            }
            .font(.system(size: PearsonStyle.textSize(13)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var examContent: some View {
        ScrollView {
            if let item = store.currentItem {
                VStack(alignment: .leading, spacing: 18) {
                    Text(item.question)
                        .font(.system(size: PearsonStyle.examTextSize(15)))
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(item.options.indices, id: \.self) { index in
                            Button {
                                store.chooseAnswer(index)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    PearsonRadio(isSelected: item.selectedIndex == index)
                                    Text(item.options[index])
                                        .font(.system(size: PearsonStyle.examTextSize(14)))
                                        .foregroundColor(PearsonStyle.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Option \(index + 1), \(item.options[index])")
                            .accessibilityValue(item.selectedIndex == index ? "Selected" : "Not selected")
                            .accessibilityIdentifier("answerOption\(index)")
                        }
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func reviewContent(width: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: width > 540 ? 3 : 2)
        let indices = store.snapshot.items.indices.filter { index in
            let item = store.snapshot.items[index]
            switch store.snapshot.reviewFilter {
            case .all: return true
            case .incomplete: return item.selectedIndex == nil
            case .flagged: return item.isFlagged
            }
        }
        return ScrollView {
            VStack(spacing: 0) {
                Text("Section Review")
                    .font(.system(size: PearsonStyle.textSize(15), weight: .bold))
                    .padding(12)
                PearsonSectionBand(title: "▣ Instructions")
                VStack(alignment: .leading, spacing: 7) {
                    Text("Below is a summary of your answers. You may review all questions, incomplete questions or flagged questions.")
                    Text("Select any question number to return to that question. End Exam submits your examination for scoring after confirmation.")
                }
                .font(.system(size: PearsonStyle.textSize(12)))
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                PearsonSectionBand(title: "▣ Practice Exam Section", trailing: "\(store.questionCount) Questions · \(store.incompleteCount) Incomplete")
                if indices.isEmpty {
                    Text("No questions match this filter.")
                        .foregroundColor(.secondary)
                        .padding(18)
                }
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(indices, id: \.self) { index in
                        let item = store.snapshot.items[index]
                        Button { store.goToQuestion(index) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: item.isFlagged ? "flag.fill" : "flag")
                                    .font(.system(size: PearsonStyle.textSize(11)))
                                    .foregroundColor(PearsonStyle.blue)
                                Text("\(index + 1)").fontWeight(.semibold)
                                Spacer(minLength: 0)
                                Text(item.selectedIndex == nil ? "Incomplete" : "Complete")
                                    .foregroundColor(item.selectedIndex == nil ? .red : .secondary)
                                    .font(.system(size: PearsonStyle.textSize(10)))
                            }
                            .font(.system(size: PearsonStyle.textSize(11)))
                            .foregroundColor(PearsonStyle.text)
                            .padding(.horizontal, 6)
                            .frame(height: 42)
                            .background(item.selectedIndex == nil ? Color.white : PearsonStyle.answered)
                            .overlay(Rectangle().stroke(PearsonStyle.line, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reviewQuestion\(index + 1)")
                    }
                }
            }
        }
    }

    private var resultsContent: some View {
        let score = store.score
        let filtered = store.snapshot.items.indices.filter { idx in
            let item = store.snapshot.items[idx]
            return item.isScored && (store.snapshot.showAllAnswers || item.selectedIndex != item.correctIndex)
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Text("Practice Exam Result")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(PearsonStyle.blue)
                Text(score.passed ? "PASS" : "FAIL")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(score.passed ? .green : .red)
                    .accessibilityIdentifier("passFailResult")
                Text("\(score.correct) / \(score.scored)")
                    .font(.system(size: 24, weight: .bold))
                Text("\(score.percentage)% on scored items · 32/40 required for PASS · \(score.unscored) unscored questions excluded")
                    .font(.system(size: PearsonStyle.textSize(12)))
                if store.snapshot.didTimeExpire {
                    Text("Time expired; the examination was submitted automatically.")
                        .foregroundColor(.red)
                }
                PearsonSectionBand(title: store.snapshot.showAllAnswers ? "Review All Scored Questions" : "Review Incorrect and Unanswered Scored Questions")
                if filtered.isEmpty {
                    Text("All scored questions answered correctly.")
                        .font(.system(size: PearsonStyle.textSize(13)))
                        .padding(.vertical, 8)
                }
                ForEach(filtered, id: \.self) { index in
                    let item = store.snapshot.items[index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Question \(index + 1): \(item.question)")
                            .font(.system(size: PearsonStyle.textSize(13), weight: .bold))
                        HStack {
                            Text("Your answer:").bold()
                            Text(item.selectedIndex.map { item.options[$0] } ?? "Unanswered")
                        }
                        .foregroundColor(item.selectedIndex == item.correctIndex ? .green : .red)
                        HStack(alignment: .top) {
                            Text("Correct answer:").bold()
                            Text(item.options[item.correctIndex])
                        }
                        .foregroundColor(.green)
                        Text("Explanation:").bold()
                        Text(item.explanation)
                        Text("Legal source: \(item.source)")
                            .font(.system(size: PearsonStyle.textSize(11)))
                            .foregroundColor(.secondary)
                    }
                    .font(.system(size: PearsonStyle.textSize(12)))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.97, green: 0.985, blue: 1))
                    .overlay(Rectangle().stroke(PearsonStyle.line))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func panelOverlay(_ active: SimulatorPanel, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.23).ignoresSafeArea().onTapGesture { panel = nil }
            VStack(spacing: 0) {
                HStack {
                    Text(active.title).font(.system(size: PearsonStyle.textSize(13), weight: .bold))
                    Spacer()
                    Button { panel = nil } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close dialog")
                }
                .foregroundColor(.white)
                .padding(10)
                .background(PearsonStyle.blue)
                ScrollView {
                    panelBody(active)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(maxHeight: min(460, height * 0.62))
                HStack {
                    Spacer()
                    if active == .submit {
                        Button("Cancel") { panel = nil }
                        Button("End Exam") {
                            panel = nil
                            store.finishExam()
                        }
                        .accessibilityIdentifier("submitExamButton")
                    } else {
                        Button("Close") { panel = nil }
                    }
                }
                .buttonStyle(.bordered)
                .tint(PearsonStyle.blue)
                .padding(8)
                .background(Color(red: 0.955, green: 0.955, blue: 0.955))
            }
            .frame(width: min(510, width - 26))
            .background(.white)
            .overlay(Rectangle().stroke(PearsonStyle.blue, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.23), radius: 9, y: 4)
        }
    }

    @ViewBuilder
    private func panelBody(_ active: SimulatorPanel) -> some View {
        switch active {
        case .examInfo:
            VStack(alignment: .leading, spacing: 10) {
                Text("Florida Psychology Laws & Rules Practice Examination").bold()
                Text("45 questions · 40 scored · 5 unscored")
                Text("Time limit: 60 minutes")
                Text("Passing score: 32/40 (80%)")
                Text("Use Previous, Next, Flag for Review, Navigator, and End Exam. All post-exam explanations are in English.")
                Text("Independent practice software; not affiliated with Pearson VUE or the Florida Board of Psychology.")
                    .foregroundColor(.secondary)
            }
        case .help:
            VStack(alignment: .leading, spacing: 10) {
                Text("Exam Controls").bold()
                Text("Flag for Review: marks the question for later review.")
                Text("Navigator: opens a list of all questions; answered questions are shaded blue.")
                Text("Previous / Next: moves between questions.")
                Text("End Exam: opens a confirmation before scoring.")
                Text("When the 60-minute timer expires, the exam is submitted automatically.")
            }
        case .navigator:
            VStack(alignment: .leading, spacing: 10) {
                Text("Select a question number to return directly to it.")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 7) {
                    ForEach(store.snapshot.items.indices, id: \.self) { index in
                        let item = store.snapshot.items[index]
                        Button {
                            store.goToQuestion(index)
                            panel = nil
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Text("\(index + 1)")
                                    .font(.system(size: PearsonStyle.textSize(12), weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(item.selectedIndex == nil ? Color.white : PearsonStyle.answered)
                                    .overlay(Rectangle().stroke(index == store.snapshot.currentIndex ? PearsonStyle.blue : PearsonStyle.line, lineWidth: index == store.snapshot.currentIndex ? 2 : 1))
                                if item.isFlagged {
                                    Image(systemName: "flag.fill")
                                        .font(.system(size: PearsonStyle.textSize(8)))
                                        .foregroundColor(.orange)
                                        .padding(3)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Blue = answered · flag = flagged · outline = current question")
                    .font(.system(size: PearsonStyle.textSize(11)))
                Button("Section Review") {
                    store.openReview()
                    panel = nil
                }
                .buttonStyle(.bordered)
                .tint(PearsonStyle.blue)
            }
        case .submit:
            VStack(alignment: .leading, spacing: 12) {
                Text("Are you sure you want to end the exam and submit it for scoring?").bold()
                Text("You can cancel to return to the exam. Unanswered questions will be scored incorrect.")
                Text("\(store.incompleteCount) unanswered question(s).")
                    .foregroundColor(.red)
                Text("Once submitted, answers cannot be changed.")
            }
        }
    }

    private func errorOverlay(_ text: String) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Unable to Start Exam").font(.headline)
                Text(text).font(.system(size: PearsonStyle.textSize(13)))
                Button("Close") { store.dismissError() }
                    .buttonStyle(.borderedProminent)
                    .tint(PearsonStyle.blue)
            }
            .padding(20)
            .frame(maxWidth: 310)
            .background(.white)
            .overlay(Rectangle().stroke(PearsonStyle.blue))
        }
    }
}