import ChatLayout
import SwiftUI
import UIKit

struct SetupCollection: UIViewControllerRepresentable {
    var model: SetupModel

    func makeUIViewController(context: Context) -> SetupChatController {
        SetupChatController(model: model)
    }

    func updateUIViewController(_ controller: SetupChatController, context: Context) {}
}

@MainActor
final class SetupChatController: UIViewController, ChatLayoutDelegate, UIGestureRecognizerDelegate, UICollectionViewDelegate {
    let model: SetupModel
    private var layout: CollectionViewChatLayout!
    private var collectionView: TranscriptCollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>!
    private let timeLayer = UIView()
    private var timeLabels: [UUID: UILabel] = [:]
    private var insetsFrozen = false
    private var displayLink: CADisplayLink?
    private var lockedOffset: CGFloat?
    private var followingTail = true
    private var catchUp = false
    private var revealPan: UIPanGestureRecognizer!
    private var bottomConstraint: NSLayoutConstraint!
    private var traitRegistration: UITraitChangeRegistration?

    init(model: SetupModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        displayLink?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        layout = CollectionViewChatLayout()
        layout.delegate = self
        layout.settings.interItemSpacing = 18
        layout.settings.additionalInsets = UIEdgeInsets(top: 8, left: 22, bottom: 8, right: 22)
        layout.settings.estimatedItemSize = CGSize(width: 320, height: 54)
        layout.supportSelfSizingInvalidation = true
        layout.keepContentOffsetAtBottomOnBatchUpdates = true
        layout.processOnlyVisibleItemsOnAnimatedBatchUpdates = false

        collectionView = TranscriptCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.keyboardDismissMode = .none
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.insetsLayoutMarginsFromSafeArea = false
        collectionView.delegate = self
        collectionView.isPrefetchingEnabled = false
        collectionView.selfSizingInvalidation = .disabled
        view.addSubview(collectionView)
        bottomConstraint = collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            bottomConstraint
        ])

        timeLayer.isUserInteractionEnabled = false
        timeLayer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timeLayer)
        NSLayoutConstraint.activate([
            timeLayer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            timeLayer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            timeLayer.topAnchor.constraint(equalTo: view.topAnchor),
            timeLayer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let registration = UICollectionView.CellRegistration<TranscriptCollectionCell, UUID> { [weak self] cell, _, id in
            guard let self else { return }
            cell.display(id: id, model: self.model, palette: self.currentPalette)
        }
        dataSource = UICollectionViewDiffableDataSource<Int, UUID>(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }

        revealPan = UIPanGestureRecognizer(target: self, action: #selector(reveal(_:)))
        revealPan.delegate = self
        collectionView.addGestureRecognizer(revealPan)
        collectionView.panGestureRecognizer.require(toFail: revealPan)
        collectionView.isDirectionalLockEnabled = true

        model.onStructureChange = { [weak self] in self?.apply(animated: true) }
        model.onLayoutChange = { [weak self] in
            self?.updateInsets()
            self?.resizeActiveCard()
        }
        model.onPickerChange = { [weak self] open in
            guard let self else { return }
            if open {
                self.lockedOffset = self.collectionView.contentOffset.y
                self.insetsFrozen = true
                self.restoreLock()
            } else {
                self.insetsFrozen = false
                self.restoreLock()
                DispatchQueue.main.async { [weak self] in
                    self?.restoreLock()
                    DispatchQueue.main.async { [weak self] in
                        self?.restoreLock()
                        self?.lockedOffset = nil
                    }
                }
            }
        }

        apply(animated: false)
        traitRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: SetupChatController, _) in
            controller.recolor()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(trackComposer))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        displayLink?.invalidate()
        displayLink = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if lockedOffset != nil {
            restoreLock()
        } else if !insetsFrozen {
            updateInsets()
        }
        layoutTimes()
        rememberContentHeight()
    }

    @objc private func trackComposer() {
        guard lockedOffset == nil, !insetsFrozen else { return }
        updateInsets()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle else { return }
        recolor()
    }

    func sizeForItem(_ chatLayout: CollectionViewChatLayout, at indexPath: IndexPath) -> ItemSize {
        .estimated(CGSize(width: chatLayout.layoutFrame.width, height: 72))
    }

    func alignmentForItem(_ chatLayout: CollectionViewChatLayout, at indexPath: IndexPath) -> ChatItemAlignment {
        .fullWidth
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        layoutTimes()
        guard scrollView.isTracking else { return }
        followingTail = distanceFromTail < 64
        if !followingTail { catchUp = false }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        collectionView.layer.removeAllAnimations()
        followingTail = distanceFromTail < 64
        let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView)
        let pullingDown = velocity.y > 0
        let atTail = distanceFromTail < 72
        scrollView.keyboardDismissMode = pullingDown && atTail ? .interactive : .none
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        scrollView.keyboardDismissMode = .none
        guard !decelerate else { return }
        settleFollow()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollView.keyboardDismissMode = .none
        settleFollow()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === revealPan else { return true }
        let velocity = revealPan.velocity(in: view)
        return velocity.x < -40 && abs(velocity.x) > abs(velocity.y) * 1.4
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { false }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }

    @objc private func reveal(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view)
        switch pan.state {
        case .changed:
            guard abs(translation.x) > abs(translation.y) else { return }
            collectionView.isScrollEnabled = false
            model.timeReveal = min(1, max(0, -translation.x / 78))
            collectionView.transform = CGAffineTransform(translationX: -78 * model.timeReveal, y: 0)
            layoutTimes()
        default:
            collectionView.isScrollEnabled = true
            withAnimation(.smooth(duration: 0.22)) { self.model.timeReveal = 0 }
            UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
                self.collectionView.transform = .identity
                self.layoutTimes()
            }
        }
    }

    private func resizeActiveCard() {
        DispatchQueue.main.async { [weak self] in
            self?.invalidateActiveSize()
        }
    }

    private func invalidateActiveSize() {
        guard let index = model.rows.lastIndex(where: {
            if case .active = $0.kind { return true }
            return false
        }) else { return }
        let path = IndexPath(item: index, section: 0)
        guard path.item < collectionView.numberOfItems(inSection: 0),
              let cell = collectionView.cellForItem(at: path) else { return }
        UIView.performWithoutAnimation {
            cell.contentView.invalidateIntrinsicContentSize()
            cell.invalidateIntrinsicContentSize()
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
        }
    }

    private var trustedContentHeight: CGFloat = 0
    private var revealQueued = false

    private func rememberContentHeight() {
        let height = collectionView.contentSize.height
        guard height > 1 else { return }
        if trustedContentHeight == 0 || height > trustedContentHeight * 0.55 {
            trustedContentHeight = height
        }
    }

    private var contentHeightIsTrusted: Bool {
        let height = collectionView.contentSize.height
        if trustedContentHeight < 200 { return height > 1 }
        return height > trustedContentHeight * 0.55
    }

    private func apply(animated: Bool) {
        followingTail = true
        revealQueued = true
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(model.rows.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.updateInsets()
            self?.layoutTimes()
        }
        _ = animated
    }

    private func settleFollow() {
        followingTail = distanceFromTail < 64
        guard followingTail, catchUp else {
            catchUp = false
            return
        }
        catchUp = false
        revealQueued = true
        updateInsets()
    }

    private var isOverflowing: Bool {
        let inset = collectionView.contentInset
        let visible = collectionView.bounds.height - inset.top - inset.bottom
        return collectionView.contentSize.height > visible + 1
    }

    private func tailOffset() -> CGFloat {
        let inset = collectionView.contentInset
        let maxOffset = collectionView.contentSize.height + inset.bottom - collectionView.bounds.height
        return max(maxOffset, -inset.top)
    }

    private var distanceFromTail: CGFloat {
        tailOffset() - collectionView.contentOffset.y
    }

    private func updateInsets() {
        if abs(bottomConstraint.constant) > 0.5 {
            bottomConstraint.constant = 0
        }
        let top = currentTopInset()
        let bottom = measuredComposerOverlap()
        let previousOffset = collectionView.contentOffset.y
        let previousBottom = collectionView.contentInset.bottom
        let delta = bottom - previousBottom
        let topChanged = abs(collectionView.contentInset.top - top) > 0.5
        let bottomChanged = abs(delta) > 1
        let dragging = collectionView.isDragging || collectionView.isTracking
        if dragging {
            if bottomChanged || topChanged {
                applyChrome(top: top, bottom: bottom)
            }
            return
        }

        if revealQueued, followingTail, collectionView.contentSize.height > 1 {
            revealQueued = false
            applyChrome(top: top, bottom: bottom)
            let rawTail = collectionView.contentSize.height + bottom - collectionView.bounds.height
            moveOffset(to: max(rawTail, -top))
            return
        }

        guard bottomChanged || topChanged else { return }
        guard !dragging else { return }

        let shift = bottomChanged
            ? composerShift(delta: delta, previousOffset: previousOffset, previousBottom: previousBottom, newBottom: bottom, top: top)
            : 0
        applyChrome(top: top, bottom: bottom)
        guard abs(shift) > 0.5 else { return }
        moveOffset(to: previousOffset + shift)
    }

    private func currentTopInset() -> CGFloat {
        let safeTop = max(view.safeAreaInsets.top, view.window?.safeAreaInsets.top ?? 0)
        return safeTop + 12 + (model.showsBackHeader ? 52 : 0)
    }

    /// The fade sitting on the composer. Resting messages stop above it.
    private let composerFade: CGFloat = 64

    /// Distance from the top of the fade to the bottom of the screen, using the composer's on-screen frame so it tracks the keyboard instead of jumping ahead of it.
    private func measuredComposerOverlap() -> CGFloat {
        let fallback = max(view.safeAreaInsets.bottom, view.window?.safeAreaInsets.bottom ?? 0) + max(model.composerInset, 72) + composerFade
        guard let probe = model.composerProbe, probe.window != nil, let window = view.window else {
            return fallback
        }
        let layer = probe.layer.presentation() ?? probe.layer
        guard layer.bounds.height > 1 else { return fallback }
        let host = window.layer.presentation() ?? window.layer
        let rect = layer.convert(layer.bounds, to: host)
        let inView = view.convert(rect, from: window)
        let overlap = view.bounds.maxY - inView.minY
        guard overlap > 1, overlap < view.bounds.height else { return fallback }
        return overlap + composerFade
    }

    /// How far the thread should move so messages stay put unless they would slide under the composer.
    private func composerShift(delta: CGFloat, previousOffset: CGFloat, previousBottom: CGFloat, newBottom: CGFloat, top: CGFloat) -> CGFloat {
        let contentBottom = collectionView.contentSize.height
        guard contentBottom > 1 else { return 0 }
        let visibleBottom = previousOffset + collectionView.bounds.height - previousBottom
        let gap = visibleBottom - contentBottom
        let atTail = gap < 36 && gap > -24
        let applied: CGFloat
        if delta > 0 {
            if gap >= delta - 0.5 {
                applied = 0
            } else if gap > 0 {
                applied = delta - gap
            } else if atTail {
                applied = delta
            } else {
                applied = 0
            }
        } else if atTail {
            applied = delta
        } else {
            applied = 0
        }
        let minimum = -top
        let maximum = max(contentBottom + newBottom - collectionView.bounds.height, minimum)
        let proposed = min(max(previousOffset + applied, minimum), maximum)
        return proposed - previousOffset
    }

    private func applyChrome(top: CGFloat, bottom: CGFloat) {
        let animations = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        collectionView.contentInset.top = top
        collectionView.contentInset.bottom = bottom
        collectionView.verticalScrollIndicatorInsets.top = top
        collectionView.verticalScrollIndicatorInsets.bottom = bottom
        UIView.setAnimationsEnabled(animations)
    }

    private func restoreLock() {
        guard let lockedOffset else { return }
        guard abs(collectionView.contentOffset.y - lockedOffset) > 0.5 else { return }
        moveOffset(to: lockedOffset)
    }

    private func moveOffset(to y: CGFloat) {
        let animations = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        collectionView.contentOffset.y = y
        UIView.setAnimationsEnabled(animations)
    }

    private func layoutTimes() {
        let visible = Set(model.rows.map(\.id))
        for id in timeLabels.keys where !visible.contains(id) {
            timeLabels[id]?.removeFromSuperview()
            timeLabels[id] = nil
        }
        for (index, row) in model.rows.enumerated() {
            let label = timeLabels[row.id] ?? makeLabel()
            timeLabels[row.id] = label
            if label.superview == nil { timeLayer.addSubview(label) }
            label.text = ClockText.label(row.date)
            label.alpha = model.timeReveal
            guard let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { continue }
            let frame = collectionView.convert(attributes.frame, to: timeLayer)
            label.frame = CGRect(x: timeLayer.bounds.width - 74, y: frame.maxY - 22, width: 66, height: 16)
        }
    }

    private func makeLabel() -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = UIColor(currentPalette.secondary)
        label.textAlignment = .right
        return label
    }

    private func recolor() {
        let palette = currentPalette
        for label in timeLabels.values {
            label.textColor = UIColor(palette.secondary)
        }
        for case let cell as TranscriptCollectionCell in collectionView.visibleCells {
            guard let id = cell.rowID else { continue }
            cell.display(id: id, model: model, palette: palette)
        }
    }

    private var currentPalette: Palette {
        traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
}

final class TranscriptCollectionView: UICollectionView {
    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {}
}

final class TranscriptCollectionCell: UICollectionViewCell {
    private let host: UIHostingController<HostedTranscript>
    private(set) var rowID: UUID?

    override init(frame: CGRect) {
        let host = UIHostingController(rootView: HostedTranscript(id: UUID(), model: nil, palette: .light))
        host.safeAreaRegions = []
        host.sizingOptions = .intrinsicContentSize
        host.view.backgroundColor = .clear
        host.view.insetsLayoutMarginsFromSafeArea = false
        self.host = host
        super.init(frame: frame)
        insetsLayoutMarginsFromSafeArea = false
        layoutMargins = .zero
        contentView.insetsLayoutMarginsFromSafeArea = false
        contentView.layoutMargins = .zero
        contentView.backgroundColor = .clear
        backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var safeAreaInsets: UIEdgeInsets { .zero }

    override func prepareForReuse() {
        super.prepareForReuse()
        rowID = nil
        host.rootView = HostedTranscript(id: UUID(), model: nil, palette: .light)
    }

    func display(id: UUID, model: SetupModel, palette: Palette) {
        let style: UIUserInterfaceStyle = palette == .dark ? .dark : .light
        if rowID != id || host.overrideUserInterfaceStyle != style {
            rowID = id
            host.rootView = HostedTranscript(id: id, model: model, palette: palette)
            host.overrideUserInterfaceStyle = style
        }
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        guard let fitted = layoutAttributes.copy() as? ChatLayoutAttributes else {
            return super.preferredLayoutAttributesFitting(layoutAttributes)
        }
        let width = layoutAttributes.size.width
        host.view.bounds.size.width = width
        host.view.layoutIfNeeded()
        let measured = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let height = max(ceil(measured), 24)
        fitted.size = CGSize(width: width, height: height)
        return fitted
    }
}

struct HostedTranscript: View {
    let id: UUID
    let model: SetupModel?
    let palette: Palette

    var body: some View {
        if let model {
            TranscriptCell(id: id, model: model)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(\.palette, palette)
        }
    }
}
