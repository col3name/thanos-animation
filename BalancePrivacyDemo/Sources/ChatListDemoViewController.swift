import UIKit

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

    private var chats: [Chat] = [
        .init(name: "Mike", time: "22:23", avatar: .mike,
              preview: .message("🤫 Sticker"), sent: true),
        .init(name: "Stocks", time: "05:35", avatar: .saved,
              preview: .video, sent: false),
        .init(name: "Designers", time: "22:16", avatar: .designers,
              preview: .designerMessage, sent: true)
    ]

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let dustEffectView = DustEffectView(frame: .zero)
    private let titleBar = UIView()
    private let folderBar = ChatFolderBar()
    private let searchBar = ChatSearchBar()
    private let editButton = UIButton(type: .system)
    private let titleAvatars = HeaderAvatarStack()
    private let titleLabel = UILabel()
    private let utilityPill = UIView()
    private let composeButton = UIButton(type: .system)
    private let floatingTabs = FloatingChatTabs()
    private var undoChat: Chat?
    private var undoChatIndex: Int?
    private var undoTimer: Timer?
    private var undoSecondsRemaining = 5
    private var undoBanner: DeleteUndoBanner?
    private var deletionBatchInFlight = false
    private var undoWaitingForDeleteBatch = false

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.overrideUserInterfaceStyle = .light
        view.backgroundColor = .white
        navigationController?.setNavigationBarHidden(true, animated: false)
        configureHeader()
        configureTable()
        configureDustEffect()
        configureBottomTabs()
    }

    private func configureDustEffect() {
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
        composeButton.translatesAutoresizingMaskIntoConstraints = false
        composeButton.addTarget(self, action: #selector(composeTapped), for: .touchUpInside)
        titleBar.addSubview(composeButton)
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
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: folderBar.bottomAnchor, constant: 3),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -78)
        ])
    }

    private func configureBottomTabs() {
        floatingTabs.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingTabs)
        NSLayoutConstraint.activate([
            floatingTabs.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            floatingTabs.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -22),
            floatingTabs.widthAnchor.constraint(equalToConstant: 188), floatingTabs.heightAnchor.constraint(equalToConstant: 61)
        ])
        floatingTabs.onSettings = { [weak self] in self?.tabTapped() }
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
            self.dismiss(animated: true) {
                self.deleteChat(named: chatName)
            }
        })
        alert.addAction(UIAlertAction(title: "Delete for me and \(chatName)", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: true) {
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
            self.dismiss(animated: true) {
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
        banner.set(secondsRemaining: undoSecondsRemaining, message: "Chat deleted for both sides.")
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
                banner.set(secondsRemaining: self.undoSecondsRemaining, message: "Chat deleted for both sides.")
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
        let deletingChatName = chats[index].name
        let image = UIGraphicsImageRenderer(size: cell.contentView.bounds.size).image { _ in
            cell.contentView.drawHierarchy(in: CGRect(origin: .zero, size: cell.contentView.bounds.size), afterScreenUpdates: false)
        }
        // Try Telegram's Metal DustEffect first. If its renderer cannot start on this
        // device, animate image fragments so deletion never silently skips the effect.
        let frame = cell.contentView.convert(cell.contentView.bounds, to: dustEffectView)
        if !dustEffectView.dissolve(image: image, at: frame) {
            let fallbackFrame = cell.contentView.convert(cell.contentView.bounds, to: view)
            animateFallbackDust(image: image, frame: fallbackFrame)
        }
        cell.contentView.isHidden = true
        cell.isUserInteractionEnabled = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let currentIndex = chats.firstIndex(where: { $0.name == deletingChatName }) else {
            onCompletion?()
            return
        }
        let row = IndexPath(row: currentIndex, section: 0)
        chats.remove(at: currentIndex)
        // Show the undo notification with the start of the Dust Effect, not after the
        // 0.8-second row-collapse animation has already finished.
        onDeletionStarted?()
        // Telegram coordinates row collapse with the dust sweep at 0.8 seconds.
        UIView.animate(withDuration: 0.8, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.tableView.performBatchUpdates({
                self.tableView.deleteRows(at: [row], with: .fade)
            }, completion: { _ in onCompletion?() })
        }
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
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates({
                tableView.deleteRows(at: [indexPath], with: .none)
            }, completion: { _ in completion?() })
        }
    }

    @objc private func editTapped() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    @objc private func composeTapped() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    @objc private func topUtilityTapped() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    private func tabTapped() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
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
        backgroundColor = .white
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 0
        layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 3)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }
    override func draw(_ rect: CGRect) {
        let gap: CGFloat = 3
        let segmentWidth = (bounds.width - 2 * gap) / 3
        let selectedRect = CGRect(x: gap + CGFloat(selectedIndex) * segmentWidth, y: 3, width: segmentWidth, height: bounds.height - 6)
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(roundedRect: selectedRect, cornerRadius: 17).fill()
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
    private let sentMark = UILabel()
    private let separator = UIView()
    private let previewThumbnail = VideoPreviewThumbnail()
    private let designerThumbnail = VideoPreviewThumbnail()
    private let dust = MessageDustPreview()
    private let designerEmoji = UILabel()
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
        sentMark.font = .systemFont(ofSize: 18, weight: .medium)
        sentMark.textColor = UIColor(red: 0.04, green: 0.75, blue: 0.15, alpha: 1)
        separator.backgroundColor = UIColor(white: 0.87, alpha: 1)
        designerEmoji.text = "↪"
        designerEmoji.font = .systemFont(ofSize: 19, weight: .medium)
        designerEmoji.textColor = UIColor(white: 0.57, alpha: 1)
        designerEmoji.textAlignment = .center
        separatorLeading = separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 86)
        previewLeading = previewLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 86)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), avatar.widthAnchor.constraint(equalToConstant: 60), avatar.heightAnchor.constraint(equalToConstant: 60),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 86), nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.heightAnchor.constraint(equalToConstant: 21),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16), timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9), timeLabel.heightAnchor.constraint(equalToConstant: 20),
            sentMark.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -3), sentMark.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
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
        sentMark.text = chat.sent ? "✓" : ""
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

    @objc private func settingsTapped() { onSettings?() }
}

private final class DeleteUndoBanner: UIView {
    var onUndo: (() -> Void)?
    private let countdown = UILabel()
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
        countdown.layer.borderColor = UIColor.white.cgColor
        countdown.layer.borderWidth = 1.5
        countdown.layer.cornerRadius = 12
        countdown.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countdown)

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
            countdown.widthAnchor.constraint(equalToConstant: 24), countdown.heightAnchor.constraint(equalToConstant: 24),
            message.leadingAnchor.constraint(equalTo: countdown.trailingAnchor, constant: 12),
            message.centerYAnchor.constraint(equalTo: centerYAnchor),
            undoButton.leadingAnchor.constraint(greaterThanOrEqualTo: message.trailingAnchor, constant: 6),
            undoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            undoButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.trailingAnchor.constraint(lessThanOrEqualTo: undoButton.leadingAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func set(secondsRemaining: Int, message text: String) {
        countdown.text = "\(secondsRemaining)"
        message.text = text
    }

    @objc private func undoTapped() { onUndo?() }
}
