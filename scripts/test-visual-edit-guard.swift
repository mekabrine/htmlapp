import Foundation

@main
struct VisualEditGuardTests {
    static func main() {
        let original = """
        <html><head><style>#habitForm {padding:10px}</style></head><body>
        <dialog id="habitDialog"><form id="habitForm">
        <h2 id="dialogTitle">New habit</h2><p class="modal-copy">Description</p>
        <label for="habitName">Habit name</label>
        <input id="habitName" type="text">
        <label for="habitTime">Time</label>
        <input id="habitTime" type="time">
        <button type="submit">Save</button>
        </form></dialog></body></html>
        """
        let broken = original.replacingOccurrences(
            of: "</head>",
            with: """
            <style>#habitForm { display:grid; gap:15px; }
            @media (min-width:460px) { #habitForm {
               grid-template-columns: minmax(0,1fr) minmax(0,1fr);
            } }</style></head>
            """
        )
        precondition(ForgeVisualEditQualityGate.isVisualRequest("redo the popup"))
        precondition(ForgeVisualEditQualityGate.targetHint(
            html: original, request: "redo the popup"
        ).contains("#habitDialog"))
        let issue = ForgeVisualEditQualityGate.issue(
            before: original, after: broken, request: "redo the popup"
        )
        precondition(issue?.contains("labels") == true,
                     "Flat form changed to two-column grid must fail QA")
        let repaired = broken.replacingOccurrences(
            of: "</head>",
            with: "<style>#habitForm {display:flex;flex-direction:column}</style></head>"
        )
        precondition(ForgeVisualEditQualityGate.issue(
            before: original, after: repaired, request: "redo the popup"
        ) == nil, "A later single-column form override must clear old grid issues")
        let safe = original.replacingOccurrences(
            of: "</head>",
            with: "<style>#habitDialog { border: 4px solid hotpink; padding: 24px; }</style></head>"
        )
        precondition(ForgeVisualEditQualityGate.issue(
            before: original, after: safe, request: "redo the popup"
        ) == nil)
        precondition(ForgeVisualEditQualityGate.issue(
            before: original, after: original, request: "redo the popup"
        ) != nil)
        precondition(ForgeVisualEditQualityGate.issue(
            before: original, after: broken, request: "save habit"
        ) == nil)
        print("Visual edit guard fixtures passed.")
    }
}
