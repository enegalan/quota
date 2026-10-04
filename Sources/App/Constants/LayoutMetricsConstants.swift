import Foundation

/// Every dimension, spacing step, and corner radius the interface uses.
///
/// Named and gathered here so that changing the density of the popover is
/// one edit rather than a search, and so a value used in two places cannot
/// drift apart — a 1pt hairline that is 1pt in one view and 2pt in another is
/// a seam nobody can see until a user does.
enum LayoutMetrics {
    // MARK: Spacing

    /// The unit every gap is a multiple of.
    static let unit: CGFloat = 4

    /// Between unrelated blocks: quota, provider, and the allowance section.
    static let sectionSpacing: CGFloat = 16

    /// Between a label and the value it describes.
    static let rowSpacing: CGFloat = 8

    /// Between adjacent action buttons in a toolbar or provider row.
    static let actionSpacing: CGFloat = 8

    /// Between the rows of a tight block, such as planned/used/remaining.
    static let lineSpacing: CGFloat = 2

    /// Inside a bordered group.
    static let inset: CGFloat = 12

    /// Below a section title.
    static let titleSpacing: CGFloat = 6

    /// Between the window's edge and the content of a detail pane.
    static let windowPadding: CGFloat = 20

    // MARK: Sizing

    /// The popover's fixed width.
    ///
    /// A menu bar popover sizes to its content, and a popover that changes width
    /// as a quota name changes is a popover that moves under the pointer. The
    /// eleven elements are laid out in one column at this width.
    static let popoverWidth: CGFloat = 320

    /// Side of the mark that says which quota the menu bar item is speaking for.
    static let menuBarMarkerSize: CGFloat = 6

    /// Default size of the management window.
    ///
    /// Wide enough for the calendar, its day strip, and a figure column beside
    /// them: at the width the detail pane first shipped with, the calendar and
    /// the day's own numbers could not both be on screen without one of them
    /// being pushed under a fold.
    static let mainWindowWidth: CGFloat = 1000
    static let mainWindowHeight: CGFloat = 680

    /// Sidebar and quota list column widths inside the main window.
    static let sidebarWidth: CGFloat = 160
    static let quotaListWidth: CGFloat = 200

    /// The narrowest the detail pane may be dragged to.
    ///
    /// Wide enough for a week of calendar columns at the minimum cell width:
    /// narrower than this and the calendar starts clipping rather than shrinking.
    static let detailMinWidth: CGFloat = 420

    /// Create-quota sheet width. Height follows the step's content: choose /
    /// install / connect are short; policy grows for the calendar when needed.
    static let sheetWidth: CGFloat = 480

    /// Ceiling for the create-quota sheet when the policy calendar is showing.
    ///
    /// Without a ceiling a custom-policy month can push the sheet past what fits
    /// on a small display; with only a floor (as before) every short step was
    /// padded with empty space.
    static let sheetMaxHeight: CGFloat = 640

    /// Narrowest a day cell may shrink before the grid stops compressing.
    ///
    /// Below this a date and a percentage cannot both fit; the grid grows with
    /// the pane above this floor rather than capping at a fixed overall width.
    static let calendarMinDayWidth: CGFloat = 40

    /// Height of one day cell in the calendar.
    ///
    /// Three lines tall — the date, the planned share, and what was spent — with
    /// room to spare, so a cell never has to clip the figure it exists to show.
    static let calendarDayHeight: CGFloat = 64

    /// Preferred day width for tests and sheet floors that need a concrete size.
    ///
    /// Not used to cap the live grid: live cells are flexible between
    /// `calendarMinDayWidth` and the space the pane offers.
    static let calendarDayWidth: CGFloat = 52

    /// A sensible width for rendering a calendar in isolation (tests, sheets).
    ///
    /// Seven preferred columns plus the gaps between them.
    static let calendarPreferredWidth: CGFloat =
        calendarDayWidth * 7 + unit * 6

    /// Height of a usage bar, in the list and under a quota's headline figures.
    static let barHeight: CGFloat = 6

    /// Height of the row of buttons beneath a quota's headline figures.
    static let barRowSpacing: CGFloat = 10

    /// Width of the allocation bar behind a calendar day.
    static let allocationBarWidth: CGFloat = 28

    /// Side of a legend's mark, so the key reads as a set of small samples of
    /// the cells it explains rather than as a list of words.
    static let legendMarkSize: CGFloat = 10

    // MARK: Corners

    /// The standard corner radius.
    static let cornerRadius: CGFloat = 6

    /// A card: the panels a window is built from.
    ///
    /// Larger than a control's radius because a card is a container rather than
    /// a control, and a container that shares a control's radius reads as a
    /// button at a glance.
    static let cardRadius: CGFloat = 10

    /// A pill: half the height it is given, so it never looks like a lozenge
    /// at one size and a stadium at another.
    static func pill(height: CGFloat) -> CGFloat {
        height / 2
    }

    // MARK: Type

    /// The smallest type the interface uses.
    ///
    /// Anything below this is unreadable at the sizes a menu bar extra is
    /// viewed at, and a menu bar item has no zoom.
    static let captionSize: CGFloat = 11

    /// Secondary text: labels, units, and supporting captions.
    static let footnoteSize: CGFloat = 12

    /// The default body size.
    static let bodySize: CGFloat = 13

    /// The figure the menu bar item is composed from.
    static let indicatorSize: CGFloat = 13

    /// A quota's headline figure, in the management window.
    static let headlineFigureSize: CGFloat = 22

    /// A section title, in caps.
    static let sectionTitleSize: CGFloat = 10

    /// How far a rendered snapshot's width may differ from the popover's.
    ///
    /// Not zero, because a renderer rounds to whole pixels and a fractional
    /// width cannot survive that. Large enough to allow the rounding, small
    /// enough that a panel which came out half the intended width still fails.
    static let snapshotWidthTolerance: CGFloat = 1

    /// How wide the percentage column of the policy editor is, so the figures
    /// line up down the rows instead of following the width of each number.
    static let weightColumnWidth: CGFloat = 48

    /// Side of the numbered circle in the creation flow's steps.
    static let stepNumberSize: CGFloat = 16

    // MARK: Colour

    /// How strongly today's cell is tinted.
    ///
    /// Low, because the tint marks a day rather than announcing it: the calendar
    /// is read at a glance, and a saturated block would outrank the percentages
    /// the user came for.
    static let todayTintOpacity: Double = 0.25

    /// How strongly a day outside the period is dimmed.
    ///
    /// Dimmed rather than hidden, because the calendar must
    /// *distinguish* those days. A day the user cannot see cannot be
    /// distinguished from a day that does not exist. Kept high enough that the
    /// date is still readable on a dark window — secondary at half strength
    /// disappears into the background.
    static let outOfPeriodOpacity: Double = 0.55

    /// How strongly a day inside the period with nothing planned is toned down.
    ///
    /// Softer than out-of-period, so an empty day is still part of the plan's
    /// month and still readable, without competing with funded days.
    static let emptyDayOpacity: Double = 0.7

    /// How strongly a cell lifts while the pointer is over it.
    ///
    /// Barely visible on its own. Its job is to answer "can I click this?" before
    /// the click, and a fill strong enough to notice from across the room would
    /// compete with the figures the cell exists to show.
    static let hoverTintOpacity: Double = 0.06

    /// How strongly the empty part of a usage bar is tinted.
    ///
    /// Enough to read as a track that is there to be filled, not enough to read as
    /// a second figure.
    static let barTrackOpacity: Double = 0.1

    /// How strongly a quota row fills under the pointer.
    ///
    /// Barely there. Its job is to answer "can I click this?" before the click;
    /// a fill strong enough to notice across a room would compete with the figure
    /// the row exists to show.
    static let hoverFillOpacity: Double = 0.1

    /// How thick the ring around the selected day is.
    ///
    /// Two points, because one is a hairline that disappears against a tinted
    /// cell and a selection the user cannot see is not a selection.
    static let selectionRingWidth: CGFloat = 2

    // MARK: Animation

    /// How long a value takes to settle when the provider's number moves.
    static let refreshAnimation: Double = 0.2

    // MARK: Dates

    /// A date written the way the user's own calendar writes it.
    ///
    /// The calendar is the user's because the date is being read beside the
    /// user's figures: a month named in another calendar's month names is a
    /// word they do not recognise on a page whose numbers they do. The template
    /// rather than a fixed pattern because the order and the separators are the
    /// locale's to decide.
    static func date(_ instant: Date, template: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: instant)
    }
}
