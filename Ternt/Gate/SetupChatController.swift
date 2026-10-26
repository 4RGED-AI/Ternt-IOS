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
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>!
    private let timeLayer = UIView()
    private var timeLabels: [UUID: UILabel] = [:]
    private var keyboardOverlap: CGFloat = 0
    private var revealPan: UIPanGestureRecognizer!

    init(model: SetupModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        layout = CollectionViewChatLayout()
        layout.delegate = self
        layout.settings.interItemSpacing = 18
        layout.settings.additionalInsets = UIEdgeInsets(top: 8, left: 22, bottom: 8, right: 22)
        layout.settings.estimatedItemSize = CGSize(width: 320, height: 72)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        if #available(iOS 16.0, *) {
            collectionView.selfSizingInvalidation = .enabledIncludingConstraints
        }
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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

        let registration = UICollectionView.CellRegistration<UICollectionViewCell, UUID> { [weak self] cell, _, id in
            guard let self else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                TranscriptCell(id: id, model: self.model)
                    .environment(\.palette, self.currentPalette)
            }
            .margins(.all, 0)
            cell.backgroundConfiguration = .clear()
        }
        dataSource = UICollectionViewDiffableDataSource<Int, UUID>(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }

        revealPan = UIPanGestureRecognizer(target: self, action: #selector(reveal(_:)))
        revealPan.delegate = self
        collectionView.addGestureRecognizer(revealPan)

        model.onStructureChange = { [weak self] in self?.apply(animated: true) }
        model.onLayoutChange = { [weak self] in self?.layout.invalidateLayout() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboard(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        apply(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateInsets()
        layoutTimes()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        collectionView.reloadData()
    }

    func alignmentForItem(_ chatLayout: CollectionViewChatLayout, at indexPath: IndexPath) -> ChatItemAlignment {
        guard model.rows.indices.contains(indexPath.item) else { return .fullWidth }
        switch model.rows[indexPath.item].kind {
        case .reply: return .trailing
        case .active: return .fullWidth
        case .welcome, .settled: return .leading
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        layoutTimes()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

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

    @objc private func keyboard(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let converted = view.convert(frame, from: nil)
        keyboardOverlap = max(0, view.bounds.maxY - converted.minY)
        let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        UIView.animate(withDuration: duration) { self.updateInsets() }
    }

    private func apply(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(model.rows.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            self?.scrollToEnd(animated)
            self?.layoutTimes()
        }
    }

    private func scrollToEnd(_ animated: Bool) {
        guard !model.rows.isEmpty else { return }
        let index = IndexPath(item: model.rows.count - 1, section: 0)
        collectionView.scrollToItem(at: index, at: .bottom, animated: animated)
    }

    private func updateInsets() {
        let bottom = keyboardOverlap > 0 ? keyboardOverlap + 84 : view.safeAreaInsets.bottom + 148
        collectionView.contentInset.top = view.safeAreaInsets.top + 12
        collectionView.contentInset.bottom = bottom
        collectionView.verticalScrollIndicatorInsets.top = collectionView.contentInset.top
        collectionView.verticalScrollIndicatorInsets.bottom = bottom
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
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        return label
    }

    private var currentPalette: Palette {
        traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
}
