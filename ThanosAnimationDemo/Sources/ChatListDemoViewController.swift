import UIKit
import Metal
import QuartzCore
import Darwin

/// Telegram chat-list recreation with a local Thanos-style dissolve on deletion.
final class ChatListDemoViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    fileprivate enum AvatarKind { case mike, saved, designers }
    fileprivate enum PreviewKind { case message(String), video, designerMessage }
    fileprivate struct Chat {
        let name: String
        let time: String
        let avatar: AvatarKind
        let preview: PreviewKind
        let sent: Bool
    }

    private let initialChats: [Chat] = [
        .init(name: "Mike", time: "22:23", avatar: .mike,
              preview: .message("🤫 Sticker"), sent: true),
        .init(name: "Stocks", time: "05:35", avatar: .saved,
              preview: .video, sent: false),
        .init(name: "Designers", time: "22:16", avatar: .designers,
              preview: .designerMessage, sent: true)
    ]
    private var chats: [Chat] = []

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateView = UIView()
    private let resetButton = UIButton(type: .system)
    // Building Metal pipelines is relatively expensive; defer it until a chat is deleted.
    private lazy var dustEffectView = DustEffectView(frame: .zero)
    private var isDustEffectConfigured = false
    private let titleBar = UIView()
    private let folderBar = ChatFolderBar()
    private let searchBar = ChatSearchBar()
    private let editButton = UIButton(type: .system)
    private let titleAvatars = HeaderAvatarStack()
    private let titleLabel = UILabel()
    private let utilityPill = UIView()
    private let composeButton = UIButton(type: .system)
    private let floatingTabs = FloatingChatTabs()
    private let performanceHUD = PerformanceHUD()
    private var undoChat: Chat?
    private var undoChatIndex: Int?
    private var undoTimer: Timer?
    private var undoSecondsRemaining = 5
    private var undoBanner: DeleteUndoBanner?
    private var deletionBatchInFlight = false
    private var undoWaitingForDeleteBatch = false
    private var hasScheduledDustWarmup = false

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.overrideUserInterfaceStyle = .light
        view.backgroundColor = .white
        navigationController?.setNavigationBarHidden(true, animated: false)
        configureHeader()
        configureTable()
        configureBottomTabs()
        chats = initialChats
        updateEmptyState()
        configurePerformanceHUD()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasScheduledDustWarmup else { return }
        hasScheduledDustWarmup = true
        // Start after the first screen is visible. DustEffectView compiles its
        // Metal pipelines on a background queue, so this does not block display.
        configureDustEffect()
        dustEffectView.prepare()
    }

    private func configureDustEffect() {
        guard !isDustEffectConfigured else { return }
        isDustEffectConfigured = true
        dustEffectView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dustEffectView)
        NSLayoutConstraint.activate([
            dustEffectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dustEffectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dustEffectView.topAnchor.constraint(equalTo: view.topAnchor),
            dustEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureHeader() {
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleBar)
        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 3),
            titleBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: 46)
        ])

        editButton.setTitle("Edit", for: .normal)
        editButton.setTitleColor(.black, for: .normal)
        editButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        styleWhitePill(editButton, radius: 22)
        applyLiquidGlass(to: editButton, cornerRadius: 22)
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        editButton.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(editButton)
        NSLayoutConstraint.activate([
            editButton.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: 16),
            editButton.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            editButton.widthAnchor.constraint(equalToConstant: 55), editButton.heightAnchor.constraint(equalToConstant: 42)
        ])

        titleAvatars.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(titleAvatars)
        titleLabel.text = "Chats"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .black
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleAvatars.leadingAnchor.constraint(equalTo: titleBar.centerXAnchor, constant: -96),
            titleAvatars.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            titleAvatars.widthAnchor.constraint(equalToConstant: 48), titleAvatars.heightAnchor.constraint(equalToConstant: 33),
            titleLabel.leadingAnchor.constraint(equalTo: titleAvatars.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor)
        ])

        utilityPill.backgroundColor = .white
        utilityPill.layer.cornerRadius = 22
        utilityPill.layer.cornerCurve = .continuous
        utilityPill.layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        utilityPill.layer.shadowOpacity = 1
        utilityPill.layer.shadowRadius = 12
        utilityPill.layer.shadowOffset = CGSize(width: 0, height: 4)
        applyLiquidGlass(to: utilityPill, cornerRadius: 22)
        utilityPill.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(utilityPill)
        NSLayoutConstraint.activate([
            utilityPill.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            utilityPill.widthAnchor.constraint(equalToConstant: 90), utilityPill.heightAnchor.constraint(equalToConstant: 42)
        ])

        let shield = UIButton(type: .system)
        shield.setImage(shieldPowerImage(), for: .normal)
        shield.tintColor = .black
        shield.addTarget(self, action: #selector(topUtilityTapped), for: .touchUpInside)
        let addFolder = UIButton(type: .system)
        addFolder.setImage(UIImage(systemName: "plus.circle.dashed"), for: .normal)
        addFolder.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .regular), forImageIn: .normal)
        addFolder.tintColor = .black
        addFolder.addTarget(self, action: #selector(topUtilityTapped), for: .touchUpInside)
        [shield, addFolder].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; utilityPill.addSubview($0) }
        NSLayoutConstraint.activate([
            shield.leadingAnchor.constraint(equalTo: utilityPill.leadingAnchor, constant: 8), shield.centerYAnchor.constraint(equalTo: utilityPill.centerYAnchor), shield.widthAnchor.constraint(equalToConstant: 30), shield.heightAnchor.constraint(equalToConstant: 34),
            addFolder.trailingAnchor.constraint(equalTo: utilityPill.trailingAnchor, constant: -7), addFolder.centerYAnchor.constraint(equalTo: utilityPill.centerYAnchor), addFolder.widthAnchor.constraint(equalToConstant: 31), addFolder.heightAnchor.constraint(equalToConstant: 34)
        ])

        composeButton.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
        composeButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 21, weight: .medium), forImageIn: .normal)
        composeButton.tintColor = .white
        composeButton.backgroundColor = UIColor(red: 0, green: 0.53, blue: 1, alpha: 1)
        composeButton.layer.cornerRadius = 22
        composeButton.layer.cornerCurve = .continuous
        composeButton.layer.borderColor = UIColor(red: 0.25, green: 0.75, blue: 1, alpha: 0.8).cgColor
        composeButton.layer.borderWidth = 1
        composeButton.layer.shadowColor = UIColor.systemBlue.withAlphaComponent(0.18).cgColor
        composeButton.layer.shadowOpacity = 1
        composeButton.layer.shadowRadius = 9
        composeButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        applyLiquidGlass(to: composeButton, cornerRadius: 22)
        composeButton.translatesAutoresizingMaskIntoConstraints = false
        composeButton.addTarget(self, action: #selector(composeTapped), for: .touchUpInside)
        titleBar.addSubview(composeButton)
        if let composeImageView = composeButton.imageView {
            composeButton.bringSubviewToFront(composeImageView)
        }
        NSLayoutConstraint.activate([
            composeButton.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -16), composeButton.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor), composeButton.widthAnchor.constraint(equalToConstant: 44), composeButton.heightAnchor.constraint(equalToConstant: 44),
            utilityPill.trailingAnchor.constraint(equalTo: composeButton.leadingAnchor, constant: -10)
        ])

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        folderBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(folderBar)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: titleBar.bottomAnchor, constant: 9),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 44),
            folderBar.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 10),
            folderBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            folderBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            folderBar.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .white
        tableView.separatorStyle = .none
        tableView.rowHeight = 76
        tableView.estimatedRowHeight = 76
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ChatRowCell.self, forCellReuseIdentifier: ChatRowCell.reuseID)
        configureEmptyState()
        tableView.backgroundView = emptyStateView
        view.addSubview(tableView)
        // Keep the folder bar above the table so its lower shadow can fall
        // over the first chat rows instead of being covered by the table.
        view.bringSubviewToFront(folderBar)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: folderBar.bottomAnchor, constant: 3),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -78)
        ])
    }

    private func configureEmptyState() {
        emptyStateView.backgroundColor = .white
        let messageLabel = UILabel()
        messageLabel.text = "All chats deleted"
        messageLabel.textColor = UIColor(white: 0.48, alpha: 1)
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textAlignment = .center

        var resetConfiguration = UIButton.Configuration.filled()
        resetConfiguration.title = "Reset"
        resetConfiguration.baseForegroundColor = .white
        resetConfiguration.baseBackgroundColor = UIColor(red: 0, green: 0.533, blue: 1, alpha: 1)
        resetConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 28, bottom: 11, trailing: 28)
        resetConfiguration.background.cornerRadius = 11
        resetConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updatedAttributes = attributes
            updatedAttributes.font = .systemFont(ofSize: 16, weight: .semibold)
            return updatedAttributes
        }
        resetButton.configuration = resetConfiguration
        resetButton.addTarget(self, action: #selector(resetChats), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [messageLabel, resetButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor)
        ])
    }

    private func updateEmptyState() {
        emptyStateView.isHidden = !chats.isEmpty
        tableView.backgroundView?.isHidden = !chats.isEmpty
    }

    @objc private func resetChats() {
        guard chats.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        undoTimer?.invalidate()
        undoTimer = nil
        undoChat = nil
        undoChatIndex = nil
        dismissUndoBanner()
        chats = initialChats
        tableView.reloadData()
        updateEmptyState()
    }

    private func configureBottomTabs() {
        floatingTabs.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingTabs)
        NSLayoutConstraint.activate([
            floatingTabs.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            floatingTabs.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -22),
            floatingTabs.widthAnchor.constraint(equalToConstant: 188), floatingTabs.heightAnchor.constraint(equalToConstant: 61)
        ])
        floatingTabs.onSettings = { [weak self] in self?.openCachePage() }
    }

    private func openCachePage() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let cachePage = CacheContentsViewController(
            warmupStatusProvider: { [weak self] in self?.dustEffectView.warmupStatusText ?? "Недоступен" },
            performanceEnabled: performanceHUD.isEnabled
        ) { [weak self] enabled in
            self?.performanceHUD.isEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: PerformanceHUD.defaultsKey)
        }
        let navigationController = UINavigationController(rootViewController: cachePage)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    private func configurePerformanceHUD() {
        performanceHUD.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(performanceHUD)
        NSLayoutConstraint.activate([
            performanceHUD.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            performanceHUD.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            performanceHUD.widthAnchor.constraint(equalToConstant: 176),
            performanceHUD.heightAnchor.constraint(equalToConstant: 118)
        ])
        performanceHUD.isEnabled = UserDefaults.standard.bool(forKey: PerformanceHUD.defaultsKey)
    }

    private func styleWhitePill(_ view: UIView, radius: CGFloat) {
        view.backgroundColor = .white
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        view.layer.shadowOpacity = 1
        view.layer.shadowRadius = 12
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    private func applyLiquidGlass(to view: UIView, cornerRadius: CGFloat) {
        guard #available(iOS 26.0, *) else { return }
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.tintColor = view.backgroundColor
        let glass = UIVisualEffectView(effect: glassEffect)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.isUserInteractionEnabled = false
        glass.layer.cornerRadius = cornerRadius
        glass.layer.cornerCurve = .continuous
        glass.clipsToBounds = true
        view.insertSubview(glass, at: 0)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glass.topAnchor.constraint(equalTo: view.topAnchor),
            glass.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.backgroundColor = .clear
    }

    private func shieldPowerImage() -> UIImage? {
        let size = CGSize(width: 22, height: 26)
        let shieldConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        let powerConfig = UIImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        guard let shield = UIImage(systemName: "shield", withConfiguration: shieldConfig),
              let power = UIImage(systemName: "power", withConfiguration: powerConfig) else { return nil }
        return UIGraphicsImageRenderer(size: size).image { _ in
            shield.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: CGRect(x: 2, y: 2, width: 18, height: 22))
            power.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: CGRect(x: 7, y: 8, width: 8, height: 8))
        }.withRenderingMode(.alwaysOriginal)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { chats.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatRowCell.reuseID, for: indexPath) as! ChatRowCell
        cell.contentView.isHidden = false
        cell.isUserInteractionEnabled = true
        cell.apply(chats[indexPath.row], isLast: indexPath.row == chats.count - 1)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            // The destructive action is only a request to open the confirmation.
            // Reporting success here makes UITableView remove the row immediately,
            // so there is no live cell left to snapshot when the user confirms.
            completion(false)
            DispatchQueue.main.async { [weak self] in
                self?.showDeleteChatConfirmation(at: indexPath)
            }
        }
        delete.image = UIImage(systemName: "trash.fill")
        let config = UISwipeActionsConfiguration(actions: [delete])
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    private func showDeleteChatConfirmation(at indexPath: IndexPath) {
        guard chats.indices.contains(indexPath.row) else { return }
        let chatName = chats[indexPath.row].name
        let alert = UIAlertController(
            title: "Delete Chat",
            message: "Permanently delete the chat with \(chatName)?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Delete just for me", style: .destructive) { [weak self] _ in
            guard let self else { return }
            // Avoid fading the chat list back in before its dust animation starts.
            self.dismiss(animated: false) {
                self.deleteChatWithUndo(named: chatName)
            }
        })
        alert.addAction(UIAlertAction(title: "Delete for me and \(chatName)", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: false) {
                self.showDeleteForEveryoneWarning(chatName: chatName)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showDeleteForEveryoneWarning(chatName: String) {
        let warning = UIAlertController(
            title: "Warning!",
            message: "This will delete all messages in this chat for both participants.",
            preferredStyle: .alert
        )
        warning.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        warning.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: false) {
                self.deleteChatWithUndo(named: chatName)
            }
        })
        present(warning, animated: true)
    }

    private func deleteChatWithUndo(named chatName: String) {
        guard !deletionBatchInFlight,
              let row = chats.firstIndex(where: { $0.name == chatName }) else { return }
        let deletedChat = chats[row]
        deletionBatchInFlight = true
        dissolveChat(
            at: IndexPath(row: row, section: 0),
            onDeletionStarted: { [weak self] in
                self?.showUndoBanner(for: deletedChat, originalIndex: row)
            },
            onCompletion: { [weak self] in self?.deleteBatchDidComplete() }
        )
    }

    private func showUndoBanner(for chat: Chat, originalIndex: Int) {
        undoTimer?.invalidate()
        undoChat = chat
        undoChatIndex = originalIndex
        undoSecondsRemaining = 5

        let banner = DeleteUndoBanner()
        banner.set(secondsRemaining: undoSecondsRemaining, message: "Chat deleted.")
        banner.startCountdown(duration: 5)
        banner.onUndo = { [weak self] in self?.undoPendingDeletion() }
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: 72)
        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            banner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -84),
            banner.heightAnchor.constraint(equalToConstant: 52)
        ])
        undoBanner?.removeFromSuperview()
        undoBanner = banner
        UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.84, initialSpringVelocity: 0.22, options: [.curveEaseOut]) {
            banner.alpha = 1
            banner.transform = .identity
        }
        undoTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.undoSecondsRemaining -= 1
            if self.undoSecondsRemaining <= 0 {
                self.finishUndoWindow()
            } else {
                banner.set(secondsRemaining: self.undoSecondsRemaining, message: "Chat deleted.")
            }
        }
    }

    private func undoPendingDeletion() {
        guard undoChat != nil, undoChatIndex != nil else { return }
        undoTimer?.invalidate()
        undoTimer = nil
        dismissUndoBanner()
        if deletionBatchInFlight {
            // The banner is intentionally available while the row collapses. Defer the
            // insert until UITableView completes its delete transaction.
            undoWaitingForDeleteBatch = true
        } else {
            restorePendingChat()
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func deleteBatchDidComplete() {
        deletionBatchInFlight = false
        guard undoWaitingForDeleteBatch else { return }
        undoWaitingForDeleteBatch = false
        restorePendingChat()
    }

    private func restorePendingChat() {
        guard let chat = undoChat, let originalIndex = undoChatIndex else { return }
        undoChat = nil
        undoChatIndex = nil
        let insertionIndex = min(originalIndex, chats.count)
        chats.insert(chat, at: insertionIndex)
        updateEmptyState()
        let indexPath = IndexPath(row: insertionIndex, section: 0)
        tableView.performBatchUpdates({
            self.tableView.insertRows(at: [indexPath], with: .fade)
        })
    }

    private func finishUndoWindow() {
        undoTimer?.invalidate()
        undoTimer = nil
        undoChat = nil
        undoChatIndex = nil
        dismissUndoBanner()
    }

    private func dismissUndoBanner() {
        guard let banner = undoBanner else { return }
        undoBanner = nil
        UIView.animate(withDuration: 0.24, animations: {
            banner.alpha = 0
            banner.transform = CGAffineTransform(translationX: 0, y: 56)
        }) { _ in banner.removeFromSuperview() }
    }

    private func deleteChat(named chatName: String) {
        guard let row = chats.firstIndex(where: { $0.name == chatName }) else { return }
        dissolveChat(at: IndexPath(row: row, section: 0))
    }

    private func dissolveChat(
        at indexPath: IndexPath,
        onDeletionStarted: (() -> Void)? = nil,
        onCompletion: (() -> Void)? = nil
    ) {
        let index = indexPath.row
        guard chats.indices.contains(index) else {
            onCompletion?()
            return
        }
        view.layoutIfNeeded()
        tableView.layoutIfNeeded()
        guard let cell = tableView.cellForRow(at: indexPath) else {
            onDeletionStarted?()
            removeChatWithoutAnimation(at: indexPath, completion: onCompletion)
            return
        }
        // Swipe-to-delete can leave a transient alpha animation on the cell.
        // Stop it and restore full visibility before capturing the row for DustEffect.
        cell.layer.removeAllAnimations()
        cell.contentView.layer.removeAllAnimations()
        cell.alpha = 1
        cell.contentView.alpha = 1
        cell.contentView.isHidden = false
        let deletingChatName = chats[index].name
        let image = UIGraphicsImageRenderer(size: cell.contentView.bounds.size).image { _ in
            cell.contentView.drawHierarchy(in: CGRect(origin: .zero, size: cell.contentView.bounds.size), afterScreenUpdates: false)
        }
        // Create the Metal renderer only for the first deletion, keeping app launch light.
        configureDustEffect()
        view.layoutIfNeeded()
        // Try Telegram's Metal DustEffect first. If its renderer cannot start on this
        // device, animate image fragments so deletion never silently skips the effect.
        let frame = cell.contentView.convert(cell.contentView.bounds, to: dustEffectView)
        let beginRowRemoval = { [weak self, weak cell] in
            guard let self, let cell else {
                onCompletion?()
                return
            }
            cell.contentView.isHidden = true
            cell.isUserInteractionEnabled = false
            guard let currentIndex = self.chats.firstIndex(where: { $0.name == deletingChatName }) else {
                onCompletion?()
                return
            }
            let row = IndexPath(row: currentIndex, section: 0)
            self.chats.remove(at: currentIndex)
            self.updateEmptyState()
            onDeletionStarted?()
            UIView.animate(withDuration: 0.8, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.tableView.performBatchUpdates({
                    self.tableView.deleteRows(at: [row], with: .none)
                }, completion: { _ in onCompletion?() })
            }
        }
        let startedMetalEffect = dustEffectView.dissolve(
            image: image,
            at: frame,
            onFirstFrame: beginRowRemoval
        )
        if !startedMetalEffect {
            let fallbackFrame = cell.contentView.convert(cell.contentView.bounds, to: view)
            animateFallbackDust(image: image, frame: fallbackFrame)
            beginRowRemoval()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func animateFallbackDust(image: UIImage, frame: CGRect) {
        guard let cgImage = image.cgImage, frame.width > 0, frame.height > 0 else { return }
        let columns = 42
        let rows = 12
        let tileWidth = frame.width / CGFloat(columns)
        let tileHeight = frame.height / CGFloat(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = CGFloat(column) * tileWidth
                let y = CGFloat(row) * tileHeight
                let sourceRect = CGRect(x: x * image.scale, y: y * image.scale,
                                        width: tileWidth * image.scale, height: tileHeight * image.scale)
                    .integral.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
                guard let tile = cgImage.cropping(to: sourceRect) else { continue }
                let fragment = UIImageView(image: UIImage(cgImage: tile, scale: image.scale, orientation: .up))
                fragment.frame = CGRect(x: frame.minX + x, y: frame.minY + y,
                                        width: tileWidth, height: tileHeight)
                fragment.isUserInteractionEnabled = false
                view.addSubview(fragment)
                let horizontalBias = (fragment.center.x - frame.midX) * 0.28
                let dx = CGFloat.random(in: 24...118) + horizontalBias
                let dy = CGFloat.random(in: -116...54)
                let duration = Double.random(in: 0.72...1.16)
                let delay = Double(column) / Double(columns) * 0.18 + Double.random(in: 0...0.06)
                UIView.animate(withDuration: duration, delay: delay, options: [.curveEaseOut, .beginFromCurrentState]) {
                    fragment.center.x += dx
                    fragment.center.y += dy
                    fragment.alpha = 0
                    fragment.transform = CGAffineTransform(rotationAngle: CGFloat.random(in: -2.4...2.4))
                        .scaledBy(x: 0.16, y: 0.16)
                } completion: { _ in fragment.removeFromSuperview() }
            }
        }
    }

    private func removeChatWithoutAnimation(at indexPath: IndexPath, completion: (() -> Void)? = nil) {
        guard chats.indices.contains(indexPath.row) else {
            completion?()
            return
        }
        chats.remove(at: indexPath.row)
        updateEmptyState()
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates({
                tableView.deleteRows(at: [indexPath], with: .none)
            }, completion: { _ in completion?() })
        }
    }

    @objc private func editTapped() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    @objc private func composeTapped() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    @objc private func topUtilityTapped() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}

private final class HeaderAvatarStack: UIView {
    private let avatarImageView = UIImageView(image: UIImage(named: "HeaderAvatars"))
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        avatarImageView.contentMode = .scaleAspectFit
        avatarImageView.frame = bounds
        avatarImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(avatarImageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class ChatSearchBar: UIView {
    private let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let placeholder = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.933, green: 0.933, blue: 0.933, alpha: 1)
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous

        icon.tintColor = UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        placeholder.text = "Search"
        placeholder.font = .systemFont(ofSize: 17, weight: .regular)
        placeholder.textColor = UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 17),
            icon.heightAnchor.constraint(equalToConstant: 17),
            icon.trailingAnchor.constraint(equalTo: placeholder.leadingAnchor, constant: -8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 13),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class ChatFolderBar: UIView {
    private let labels = ["All", "Telegram", "Awesome"]
    private let selectedIndex = 2
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        // Match the search field's continuous outer silhouette while keeping the
        // folder bar's white surface consistent with the title bar.
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 0
        layer.shadowColor = UIColor.black.withAlphaComponent(0.06).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }
    override func draw(_ rect: CGRect) {
        // Clip the complete bar surface and its custom-drawn segments to the
        // same capsule silhouette as the search bar.
        let context = UIGraphicsGetCurrentContext()
        let outerPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2)
        context?.saveGState()
        outerPath.addClip()
        UIColor.white.setFill()
        outerPath.fill()

        let gap: CGFloat = 3
        let segmentWidth = (bounds.width - 2 * gap) / 3
        let selectedRect = CGRect(x: gap + CGFloat(selectedIndex) * segmentWidth, y: 3, width: segmentWidth, height: bounds.height - 6)
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(roundedRect: selectedRect, cornerRadius: selectedRect.height / 2).fill()
        for index in 0..<3 {
            let title = labels[index] as NSString
            let font = UIFont.systemFont(ofSize: 15, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            let textSize = title.size(withAttributes: attributes)
            let centerX = CGFloat(index) * segmentWidth + segmentWidth / 2 + gap
            let x = centerX - textSize.width / 2 - (index == 1 ? 7 : 0)
            let y = (bounds.height - textSize.height) / 2 - 1
            title.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
            if index == 1 {
                let badge = CGRect(x: centerX + textSize.width / 2 - 1, y: (bounds.height - 18) / 2, width: 18, height: 18)
                UIColor(white: 0.72, alpha: 1).setFill()
                UIBezierPath(ovalIn: badge).fill()
                let badgeText = "2" as NSString
                let badgeFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
                let badgeAttrs: [NSAttributedString.Key: Any] = [.font: badgeFont, .foregroundColor: UIColor.white]
                let badgeSize = badgeText.size(withAttributes: badgeAttrs)
                badgeText.draw(at: CGPoint(x: badge.midX - badgeSize.width / 2, y: badge.midY - badgeSize.height / 2 - 1), withAttributes: badgeAttrs)
            }
        }
        context?.restoreGState()
    }
}

private final class ChatRowCell: UITableViewCell {
    static let reuseID = "ChatRowCell"
    private let avatar = ChatAvatarView()
    private let nameLabel = UILabel()
    private let previewLabel = UILabel()
    private let youLabel = UILabel()
    private let designerPreviewLabel = UILabel()
    private let timeLabel = UILabel()
    private let sentMark = UIImageView()
    private let separator = UIView()
    private let previewThumbnail = VideoPreviewThumbnail()
    private let designerThumbnail = VideoPreviewThumbnail()
    private let dust = MessageDustPreview()
    private let designerEmoji = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.right.fill"))
    private var separatorLeading: NSLayoutConstraint!
    private var previewLeading: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .white
        contentView.backgroundColor = .white
        selectionStyle = .none
        [avatar, nameLabel, previewLabel, youLabel, designerPreviewLabel, timeLabel, sentMark, separator, previewThumbnail, designerThumbnail, dust, designerEmoji].forEach { contentView.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .black
        previewLabel.font = .systemFont(ofSize: 15, weight: .regular)
        previewLabel.textColor = UIColor(red: 0.553, green: 0.553, blue: 0.576, alpha: 1)
        previewLabel.lineBreakMode = .byTruncatingTail
        youLabel.font = .systemFont(ofSize: 15)
        youLabel.textColor = .black
        youLabel.text = "You"
        designerPreviewLabel.font = .systemFont(ofSize: 15)
        designerPreviewLabel.textColor = UIColor(red: 0.553, green: 0.553, blue: 0.576, alpha: 1)
        designerPreviewLabel.text = "Quick Photos Send — Send Photos…"
        designerPreviewLabel.lineBreakMode = .byTruncatingTail
        timeLabel.font = .systemFont(ofSize: 14, weight: .regular)
        timeLabel.textColor = UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1)
        timeLabel.textAlignment = .right
        sentMark.contentMode = .scaleAspectFit
        separator.backgroundColor = UIColor(white: 0.87, alpha: 1)
        designerEmoji.tintColor = UIColor(white: 0.57, alpha: 1)
        designerEmoji.contentMode = .scaleAspectFit
        separatorLeading = separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 86)
        previewLeading = previewLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 86)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), avatar.widthAnchor.constraint(equalToConstant: 60), avatar.heightAnchor.constraint(equalToConstant: 60),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 86), nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.heightAnchor.constraint(equalToConstant: 21),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16), timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9), timeLabel.heightAnchor.constraint(equalToConstant: 20),
            sentMark.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -3), sentMark.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor), sentMark.widthAnchor.constraint(equalToConstant: 20), sentMark.heightAnchor.constraint(equalToConstant: 16),
            separatorLeading, separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16), separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor), separator.heightAnchor.constraint(equalToConstant: 0.5),
            previewThumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 86), previewThumbnail.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 1), previewThumbnail.widthAnchor.constraint(equalToConstant: 18), previewThumbnail.heightAnchor.constraint(equalToConstant: 18),
            designerEmoji.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 86), designerEmoji.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 49), designerEmoji.widthAnchor.constraint(equalToConstant: 16), designerEmoji.heightAnchor.constraint(equalToConstant: 20),
            designerThumbnail.leadingAnchor.constraint(equalTo: designerEmoji.trailingAnchor, constant: 4), designerThumbnail.centerYAnchor.constraint(equalTo: designerEmoji.centerYAnchor), designerThumbnail.widthAnchor.constraint(equalToConstant: 18), designerThumbnail.heightAnchor.constraint(equalToConstant: 18),
            youLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 86), youLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 30), youLabel.heightAnchor.constraint(equalToConstant: 19),
            designerPreviewLabel.leadingAnchor.constraint(equalTo: designerThumbnail.trailingAnchor, constant: 6), designerPreviewLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15), designerPreviewLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 49), designerPreviewLabel.heightAnchor.constraint(equalToConstant: 20),
            previewLeading, previewLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15), previewLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28), previewLabel.heightAnchor.constraint(equalToConstant: 22),
            dust.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 86), dust.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15), dust.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 34), dust.heightAnchor.constraint(equalToConstant: 37)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        alpha = 1
        contentView.alpha = 1
        contentView.isHidden = false
        isUserInteractionEnabled = true
    }

    func apply(_ chat: ChatListDemoViewController.Chat, isLast: Bool) {
        alpha = 1
        contentView.alpha = 1
        contentView.isHidden = false
        isUserInteractionEnabled = true
        nameLabel.text = chat.name
        timeLabel.text = chat.time
        // Match Telegram's thin green sent/read ticks with crisp vector paths.
        sentMark.image = chat.sent ? Self.tickImage(double: false) : nil
        sentMark.isHidden = !chat.sent
        avatar.kind = chat.avatar
        switch chat.preview {
        case let .message(text):
            previewLabel.text = text
            previewLabel.isHidden = false
            youLabel.isHidden = true
            designerPreviewLabel.isHidden = true
            previewThumbnail.isHidden = true
            designerThumbnail.isHidden = true
            designerEmoji.isHidden = true
            previewLeading.constant = 86
            dust.isHidden = true
        case .video:
            previewLabel.text = "Video"
            previewLeading.constant = 110
            previewLabel.isHidden = false
            youLabel.isHidden = true
            designerPreviewLabel.isHidden = true
            previewThumbnail.isHidden = false
            designerThumbnail.isHidden = true
            designerEmoji.isHidden = true
            dust.isHidden = true
        case .designerMessage:
            previewLabel.isHidden = true
            previewThumbnail.isHidden = true
            youLabel.isHidden = false
            designerPreviewLabel.isHidden = false
            designerEmoji.isHidden = false
            designerThumbnail.isHidden = false
            dust.isHidden = true
        }
        previewLabel.textColor = UIColor(red: 0.553, green: 0.553, blue: 0.576, alpha: 1)
        previewLabel.font = .systemFont(ofSize: 15)
        separatorLeading.constant = isLast ? 0 : 86
    }

    private static func tickImage(double: Bool) -> UIImage {
        let size = CGSize(width: double ? 28 : 14, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let color = UIColor(red: 0.04, green: 0.75, blue: 0.15, alpha: 1)
            let paths: [[CGPoint]] = double
                ? [[CGPoint(x: 1, y: 10), CGPoint(x: 5.5, y: 15), CGPoint(x: 15, y: 3)],
                   [CGPoint(x: 8, y: 10), CGPoint(x: 12.5, y: 15), CGPoint(x: 25.5, y: 2)]]
                : [[CGPoint(x: 1, y: 10), CGPoint(x: 5.5, y: 15), CGPoint(x: 15, y: 3)]]
            color.setStroke()
            for points in paths {
                let path = UIBezierPath()
                path.move(to: points[0])
                path.addLine(to: points[1])
                path.addLine(to: points[2])
                path.lineWidth = 2.4
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        }
    }
}

private final class ChatAvatarView: UIView {
    var kind: ChatListDemoViewController.AvatarKind = .mike { didSet { updateAvatar() } }
    private let photoView = UIImageView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 30
        layer.masksToBounds = true
        photoView.frame = bounds
        photoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        photoView.contentMode = .scaleAspectFill
        addSubview(photoView)
        updateAvatar()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); photoView.frame = bounds }
    private func updateAvatar() {
        switch kind {
        // These two images are cropped from the reference screen so the demo row
        // art, framing, and photo crop match the original at the same display size.
        case .mike: photoView.image = UIImage(named: "ChatMikeAvatar", in: .main, compatibleWith: traitCollection)
        case .designers: photoView.image = UIImage(named: "ChatDesignersAvatar", in: .main, compatibleWith: traitCollection)
        case .saved: photoView.image = nil
        }
        setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        switch kind {
        case .mike:
            break
        case .saved:
            let colors = [UIColor(red: 0.31, green: 0.75, blue: 0.96, alpha: 1), UIColor(red: 0.11, green: 0.57, blue: 0.88, alpha: 1)]
            let context = UIGraphicsGetCurrentContext()
            context?.saveGState()
            context?.clip(to: rect)
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0, 1]) {
                context?.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: rect.maxY), options: [])
            }
            context?.restoreGState()
            let symbol = UIImage(systemName: "bookmark.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: bounds.midX - 11, y: bounds.midY - 14, width: 22, height: 28))
        case .designers:
            break
        }
    }
}

private final class VideoPreviewThumbnail: UIView {
    override init(frame: CGRect) { super.init(frame: frame); layer.cornerRadius = 2; clipsToBounds = true; isUserInteractionEnabled = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        UIImage(named: "VideoPreviewIcon")?.draw(in: rect)
    }
}

private final class MessageDustPreview: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        var seed: UInt64 = 0xA5EED
        for index in 0..<220 {
            seed = 2862933555777941757 &* seed &+ 3037000493
            let randomX = CGFloat(seed % 10_000) / 10_000
            seed = 2862933555777941757 &* seed &+ 3037000493
            let randomY = CGFloat(seed % 10_000) / 10_000
            let radius = CGFloat(seed % 12 + 2) / 10
            let point: CGPoint
            if index < 110 {
                point = CGPoint(x: rect.width * (0.76 + randomX * 0.24), y: randomY * 18)
            } else {
                point = CGPoint(x: randomX * rect.width * 0.42, y: 17 + randomY * 19)
            }
            UIColor(white: 0.56, alpha: CGFloat(seed % 60 + 20) / 100).setFill()
            UIRectFill(CGRect(x: point.x, y: point.y, width: radius, height: radius))
        }
    }
}

private final class FloatingChatTabs: UIView {
    var onSettings: (() -> Void)?
    private let active = UIView()
    private let chatsButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.cornerRadius = 29
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 0.96, alpha: 1).cgColor
        layer.shadowColor = UIColor.black.withAlphaComponent(0.12).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 5)
        active.backgroundColor = UIColor(white: 0.92, alpha: 1)
        active.layer.cornerRadius = 25
        active.layer.cornerCurve = .continuous
        active.translatesAutoresizingMaskIntoConstraints = false
        addSubview(active)
        chatsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chatsButton); addSubview(settingsButton)
        NSLayoutConstraint.activate([
            active.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), active.topAnchor.constraint(equalTo: topAnchor, constant: 4), active.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), active.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            chatsButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), chatsButton.topAnchor.constraint(equalTo: topAnchor, constant: 4), chatsButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), chatsButton.widthAnchor.constraint(equalTo: active.widthAnchor),
            settingsButton.leadingAnchor.constraint(equalTo: active.trailingAnchor), settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4), settingsButton.topAnchor.constraint(equalTo: topAnchor, constant: 4), settingsButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        configureButton(chatsButton, title: "Chats", symbol: "bubble.left.and.bubble.right.fill", color: UIColor(red: 0, green: 0.533, blue: 1, alpha: 1), badge: "2", iconSize: 24)
        configureButton(settingsButton, title: "Settings", symbol: "person.crop.circle.fill", color: .black, badge: "923", iconSize: 22)
        chatsButton.addTarget(self, action: #selector(chatsTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureButton(_ button: UIButton, title: String, symbol: String, color: UIColor, badge: String, iconSize: CGFloat = 18) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = title == "Chats"
            ? Self.chatsTabIcon()
            : UIImage(named: "SettingsTabAvatar")?.withRenderingMode(.alwaysOriginal) ?? UIImage(systemName: symbol)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
        configuration.imagePlacement = .top
        configuration.imagePadding = 2
        configuration.contentInsets = title == "Settings"
            ? NSDirectionalEdgeInsets(top: 0, leading: -6, bottom: 0, trailing: 6)
            : .zero
        configuration.baseForegroundColor = color
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 11, weight: .medium)
            return outgoing
        }
        button.configuration = configuration
        let badgeView = UILabel()
        badgeView.text = badge
        badgeView.font = .systemFont(ofSize: 12, weight: .medium)
        badgeView.textColor = .white
        badgeView.textAlignment = .center
        badgeView.backgroundColor = UIColor(red: 0.996, green: 0.22, blue: 0.235, alpha: 1)
        badgeView.layer.cornerRadius = 9
        badgeView.clipsToBounds = true
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(badgeView)
        NSLayoutConstraint.activate([
            badgeView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: badge == "2" ? -17 : -6), badgeView.topAnchor.constraint(equalTo: button.topAnchor, constant: 2), badgeView.widthAnchor.constraint(equalToConstant: badge.count > 2 ? 31 : 18), badgeView.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    private static func chatsTabIcon() -> UIImage {
        UIImage(named: "ChatsTabIcon")?.withRenderingMode(.alwaysOriginal)
            ?? UIImage(systemName: "bubble.left.and.bubble.right.fill")!.withRenderingMode(.alwaysOriginal)
    }

    @objc private func chatsTapped() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    @objc private func settingsTapped() { onSettings?() }
}

private final class DeleteUndoBanner: UIView {
    var onUndo: (() -> Void)?
    private let countdown = UILabel()
    private let countdownTrack = CAShapeLayer()
    private let countdownProgress = CAShapeLayer()
    private let message = UILabel()
    private let undoButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.30, alpha: 0.97)
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous

        countdown.textColor = .white
        countdown.font = .systemFont(ofSize: 16, weight: .regular)
        countdown.textAlignment = .center
        countdown.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countdown)
        [countdownTrack, countdownProgress].forEach {
            $0.fillColor = UIColor.clear.cgColor
            $0.strokeColor = UIColor.white.cgColor
            $0.lineWidth = 1.5
            $0.lineCap = .round
            layer.addSublayer($0)
        }

        message.textColor = .white
        message.font = .systemFont(ofSize: 15, weight: .semibold)
        message.lineBreakMode = .byTruncatingTail
        message.translatesAutoresizingMaskIntoConstraints = false
        addSubview(message)

        undoButton.setTitle("Undo", for: .normal)
        undoButton.setTitleColor(UIColor(red: 0.40, green: 0.82, blue: 0.97, alpha: 1), for: .normal)
        undoButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        undoButton.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)
        undoButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(undoButton)

        NSLayoutConstraint.activate([
            countdown.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            countdown.centerYAnchor.constraint(equalTo: centerYAnchor),
            countdown.widthAnchor.constraint(equalToConstant: 28), countdown.heightAnchor.constraint(equalToConstant: 28),
            message.leadingAnchor.constraint(equalTo: countdown.trailingAnchor, constant: 12),
            message.centerYAnchor.constraint(equalTo: centerYAnchor),
            undoButton.leadingAnchor.constraint(greaterThanOrEqualTo: message.trailingAnchor, constant: 6),
            undoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            undoButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.trailingAnchor.constraint(lessThanOrEqualTo: undoButton.leadingAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let circleRect = CGRect(x: 12, y: (bounds.height - 28) / 2, width: 28, height: 28)
        let path = UIBezierPath(arcCenter: CGPoint(x: circleRect.midX, y: circleRect.midY), radius: 12.4,
                                startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: true).cgPath
        countdownTrack.frame = bounds
        countdownTrack.path = path
        countdownTrack.opacity = 0.28
        countdownProgress.frame = bounds
        countdownProgress.path = path
    }

    func startCountdown(duration: TimeInterval) {
        countdownProgress.removeAnimation(forKey: "countdown")
        countdownProgress.strokeStart = 0
        let animation = CABasicAnimation(keyPath: "strokeStart")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        countdownProgress.add(animation, forKey: "countdown")
    }

    func set(secondsRemaining: Int, message text: String) {
        countdown.text = "\(secondsRemaining)"
        message.text = text
    }

    @objc private func undoTapped() { onUndo?() }
}

private final class CacheContentsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private struct Entry {
        let name: String
        let detail: String
        let size: Int64
        let fileURL: URL?
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let summaryLabel = UILabel()
    private let dustStatusLabel = UILabel()
    private let performanceSwitch = UISwitch()
    private let clearButton = UIButton(type: .system)
    private let warmupStatusProvider: () -> String
    private let performanceEnabled: Bool
    private let onPerformanceToggle: (Bool) -> Void
    private var statusTimer: Timer?
    private var entries: [Entry] = []
    private var totalBytes: Int64 = 0

    init(warmupStatusProvider: @escaping () -> String, performanceEnabled: Bool, onPerformanceToggle: @escaping (Bool) -> Void) {
        self.warmupStatusProvider = warmupStatusProvider
        self.performanceEnabled = performanceEnabled
        self.onPerformanceToggle = onPerformanceToggle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Кэш приложения"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))

        summaryLabel.font = .systemFont(ofSize: 15, weight: .regular)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(summaryLabel)

        dustStatusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        dustStatusLabel.textColor = .label
        dustStatusLabel.numberOfLines = 0
        dustStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dustStatusLabel)

        let performanceLabel = UILabel()
        performanceLabel.text = "Показывать производительность"
        performanceLabel.font = .systemFont(ofSize: 15, weight: .medium)
        performanceLabel.translatesAutoresizingMaskIntoConstraints = false
        performanceSwitch.isOn = performanceEnabled
        performanceSwitch.addTarget(self, action: #selector(performanceSwitchChanged), for: .valueChanged)
        performanceSwitch.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(performanceLabel)
        view.addSubview(performanceSwitch)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        clearButton.setTitle("Очистить все кэши", for: .normal)
        clearButton.setTitleColor(.white, for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        clearButton.backgroundColor = .systemRed
        clearButton.layer.cornerRadius = 14
        clearButton.addTarget(self, action: #selector(clearAllCaches), for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clearButton)

        NSLayoutConstraint.activate([
            summaryLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            performanceLabel.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 16),
            performanceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            performanceLabel.centerYAnchor.constraint(equalTo: performanceSwitch.centerYAnchor),
            performanceSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            performanceSwitch.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),
            dustStatusLabel.topAnchor.constraint(equalTo: performanceSwitch.bottomAnchor, constant: 12),
            dustStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            dustStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tableView.topAnchor.constraint(equalTo: dustStatusLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -12),
            clearButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            clearButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            clearButton.heightAnchor.constraint(equalToConstant: 52)
        ])
        reloadCacheEntries()
        updateDustStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.updateDustStatus()
        }
    }

    deinit { statusTimer?.invalidate() }

    private func updateDustStatus() {
        dustStatusLabel.text = "DustEffectView · \(warmupStatusProvider())"
    }

    @objc private func performanceSwitchChanged() {
        onPerformanceToggle(performanceSwitch.isOn)
    }

    private func reloadCacheEntries() {
        entries.removeAll()
        totalBytes = 0
        let fileManager = FileManager.default
        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let enumerator = fileManager.enumerator(at: cachesURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { continue }
                let size = Int64(values.fileSize ?? 0)
                totalBytes += size
                entries.append(Entry(name: url.lastPathComponent, detail: url.deletingLastPathComponent().path, size: size, fileURL: url))
            }
        }

        let urlCache = URLCache.shared
        let urlCacheSize = Int64(urlCache.currentDiskUsage + urlCache.currentMemoryUsage)
        entries.append(Entry(
            name: "URLCache",
            detail: "Память: \(ByteCountFormatter.string(fromByteCount: Int64(urlCache.currentMemoryUsage), countStyle: .file)); диск: \(ByteCountFormatter.string(fromByteCount: Int64(urlCache.currentDiskUsage), countStyle: .file))",
            size: urlCacheSize,
            fileURL: nil
        ))
        totalBytes += urlCacheSize
        entries.sort {
            if $0.name == "URLCache" { return $1.name != "URLCache" }
            if $1.name == "URLCache" { return false }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        summaryLabel.text = "Найдено элементов: \(entries.count)\nОбщий размер: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
        clearButton.isEnabled = totalBytes > 0
        clearButton.alpha = clearButton.isEnabled ? 1 : 0.55
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { entries.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let entry = entries[indexPath.row]
        cell.textLabel?.text = entry.name
        cell.detailTextLabel?.text = "\(entry.detail) · \(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = entries[indexPath.row]
        let viewer = CacheFileViewerViewController(name: entry.name, fileURL: entry.fileURL, size: entry.size, detail: entry.detail)
        navigationController?.pushViewController(viewer, animated: true)
    }

    @objc private func clearAllCaches() {
        URLCache.shared.removeAllCachedResponses()
        if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let cachedItems = try? FileManager.default.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil) {
            for itemURL in cachedItems { try? FileManager.default.removeItem(at: itemURL) }
        }
        reloadCacheEntries()
    }

    @objc private func close() { dismiss(animated: true) }
}

private final class CacheFileViewerViewController: UIViewController {
    private let name: String
    private let fileURL: URL?
    private let fileSize: Int64
    private let detail: String
    private let textView = UITextView()

    init(name: String, fileURL: URL?, size: Int64, detail: String) {
        self.name = name
        self.fileURL = fileURL
        self.fileSize = size
        self.detail = detail
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = name
        view.backgroundColor = .systemBackground
        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
        textView.text = contents()
    }

    private func contents() -> String {
        guard let fileURL else {
            return "URLCache — кэш сетевых ответов, управляемый iOS.\n\nРазмер в памяти и на диске: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)).\n\nURLCache не предоставляет приложению список отдельных файлов или API для чтения их необработанного содержимого."
        }
        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let maxBytes = 1_048_576
            let shownData = data.prefix(maxBytes)
            let wasTruncated = data.count > maxBytes
            if let string = String(data: shownData, encoding: .utf8), Self.isMostlyReadable(string) {
                return string + (wasTruncated ? "\n\n… содержимое сокращено до первых 1 МБ из \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))." : "")
            }
            let binaryInfo = Self.binaryAnalysis(data: data, name: name)
            var lines: [String] = []
            let bytes = Array(shownData)
            for offset in stride(from: 0, to: bytes.count, by: 16) {
                let end = min(offset + 16, bytes.count)
                let row = bytes[offset..<end]
                let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ")
                let hexColumn = hex.padding(toLength: 47, withPad: " ", startingAt: 0)
                let ascii = row.map { byte -> Character in
                    (byte >= 32 && byte < 127) ? Character(UnicodeScalar(byte)) : "."
                }
                let offsetText = String(offset, radix: 16).uppercased().padding(toLength: 8, withPad: "0", startingAt: 0)
                lines.append("\(offsetText)  \(hexColumn)  \(String(ascii))")
            }
            if wasTruncated {
                lines.append("\n… показаны первые 1 МБ из \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)).")
            }
            return binaryInfo + "\n\nБинарный файл · \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))\n\(detail)\n\n" + lines.joined(separator: "\n")
        } catch {
            return "Не удалось прочитать файл.\n\(error.localizedDescription)"
        }
    }

    private static func isMostlyReadable(_ string: String) -> Bool {
        string.unicodeScalars.allSatisfy { scalar in
            CharacterSet.controlCharacters.contains(scalar) == false || scalar == "\n" || scalar == "\r" || scalar == "\t"
        }
    }

    private static func binaryAnalysis(data: Data, name: String) -> String {
        let header = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
        let isMetalFunctionIndex = name == "functions.list" && data.starts(with: [0x45, 0x36, 0x27, 0x18])
        var result: String
        if isMetalFunctionIndex {
            result = "АНАЛИЗ: индекс кэша функций Metal\nЭто служебный бинарный индекс для ускорения работы GPU. Исходный MSL-код в этом файле не хранится; декомпилировать его в исходный шейдер нельзя."
        } else if name == "functions.data" {
            result = "АНАЛИЗ: данные кэша функций Metal\nЭто бинарные данные графического кэша. Они не являются исходным кодом приложения или шейдера."
        } else if name.hasSuffix(".dyld4") {
            result = "АНАЛИЗ: кэш загрузчика dyld4\nСлужебные данные iOS для ускорения запуска приложения; это не исходный код приложения."
        } else {
            result = "АНАЛИЗ: неизвестный бинарный формат\nЗаголовок файла: \(header.isEmpty ? "пустой файл" : header)"
        }

        let strings = readableStrings(in: data).prefix(80)
        if !strings.isEmpty {
            result += "\n\nНайденные читаемые строки:\n" + strings.joined(separator: "\n")
        } else {
            result += "\n\nЧитаемых строк не найдено."
        }
        return result
    }

    private static func readableStrings(in data: Data) -> [String] {
        var found: [String] = []
        var current: [UInt8] = []
        func flush() {
            guard current.count >= 4 else { current.removeAll(keepingCapacity: true); return }
            let value = String(decoding: current, as: UTF8.self)
            if !found.contains(value) { found.append(value) }
            current.removeAll(keepingCapacity: true)
        }
        for byte in data {
            if (32...126).contains(byte) {
                current.append(byte)
            } else {
                flush()
            }
        }
        flush()
        return found
    }
}

final class PerformanceTelemetry {
    static let shared = PerformanceTelemetry()
    private let lock = NSLock()
    private var cpuMilliseconds: Double = 0
    private var gpuMilliseconds: Double = 0

    func updateCPU(milliseconds: Double) {
        lock.lock(); cpuMilliseconds = milliseconds; lock.unlock()
    }

    func updateGPU(milliseconds: Double) {
        lock.lock(); gpuMilliseconds = milliseconds; lock.unlock()
    }

    func snapshot() -> (cpu: Double, gpu: Double) {
        lock.lock(); defer { lock.unlock() }
        return (cpuMilliseconds, gpuMilliseconds)
    }
}

private final class PerformanceHUD: UIView {
    // Start with the profiler hidden; this new key also ignores the old
    // development value that may have left the HUD enabled on test devices.
    static let defaultsKey = "showPerformanceHUD.defaultOff"
    var isEnabled = false {
        didSet {
            isHidden = !isEnabled
            if isEnabled { startUpdates() } else { stopUpdates() }
        }
    }

    private let metricsLabel = UILabel()
    private let chart = PerformanceHUDChart()
    private let device = MTLCreateSystemDefaultDevice()
    private var displayLink: CADisplayLink?
    private var lastFPSWindow: CFTimeInterval = 0
    private var frameCount = 0
    private var currentFPS: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.08, alpha: 0.82)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        clipsToBounds = true

        metricsLabel.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        metricsLabel.textColor = .white
        metricsLabel.numberOfLines = 0
        metricsLabel.translatesAutoresizingMaskIntoConstraints = false
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metricsLabel)
        addSubview(chart)
        NSLayoutConstraint.activate([
            metricsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            metricsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            metricsLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            chart.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            chart.heightAnchor.constraint(equalToConstant: 25)
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func startUpdates() {
        guard displayLink == nil else { return }
        lastFPSWindow = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        let maximumFPS = UIScreen.main.maximumFramesPerSecond
        if maximumFPS >= 120 {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        }
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopUpdates() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        frameCount += 1
        let now = CACurrentMediaTime()
        let window = now - lastFPSWindow
        guard window >= 0.5 else { return }
        currentFPS = Double(frameCount) / window
        frameCount = 0
        lastFPSWindow = now
        let timing = PerformanceTelemetry.shared.snapshot()
        let resolution = "\(Int(UIScreen.main.nativeBounds.width))×\(Int(UIScreen.main.nativeBounds.height))"
        let scale = String(format: "%.1f", UIScreen.main.scale)
        let refresh = Int(link.targetTimestamp > link.timestamp ? 1 / (link.targetTimestamp - link.timestamp) : 60)
        let memory = Self.residentMemoryMegabytes()
        metricsLabel.text = "\(device?.name ?? "Metal GPU")  [\(resolution)]\n\(scale)x  FPS: \(String(format: "%.1f", currentFPS))  [\(refresh)Hz]\nCPU frame: \(String(format: "%.2f", timing.cpu)) ms\nDust GPU: \(String(format: "%.2f", timing.gpu)) ms   Mem: \(String(format: "%.1f", memory)) MB"
        chart.append(cpu: timing.cpu, gpu: timing.gpu)
    }

    private static func residentMemoryMegabytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }
}

private final class PerformanceHUDChart: UIView {
    private var cpuSamples: [CGFloat] = []
    private var gpuSamples: [CGFloat] = []

    func append(cpu: Double, gpu: Double) {
        cpuSamples.append(CGFloat(min(1, cpu / 33.3)))
        gpuSamples.append(CGFloat(min(1, gpu / 33.3)))
        if cpuSamples.count > 60 { cpuSamples.removeFirst() }
        if gpuSamples.count > 60 { gpuSamples.removeFirst() }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.25).cgColor)
        context.setLineWidth(0.5)
        for i in 0...4 {
            let y = CGFloat(i) * rect.height / 4
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: rect.width, y: y))
        }
        context.strokePath()
        draw(samples: cpuSamples, color: .systemBlue, in: rect)
        draw(samples: gpuSamples, color: .systemGreen, in: rect)
    }

    private func draw(samples: [CGFloat], color: UIColor, in rect: CGRect) {
        guard samples.count > 1 else { return }
        let path = UIBezierPath()
        for (index, value) in samples.enumerated() {
            let point = CGPoint(x: CGFloat(index) / 59 * rect.width, y: rect.height * (1 - value))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        color.setStroke()
        path.lineWidth = 1.2
        path.stroke()
    }
}
