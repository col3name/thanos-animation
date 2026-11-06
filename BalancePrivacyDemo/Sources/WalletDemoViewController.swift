import UIKit

final class WalletDemoViewController: UIViewController {
    private let balanceView = PrivacyBalanceView()
    private let privacyButton = UIButton(type: .system)
    private let stateLabel = UILabel()
    private var assetAmounts: [(label: UILabel, original: String)] = []
    private let walletCard = UIView()
    private let cardGradient = CAGradientLayer()
    private let cardGlow = CAGradientLayer()

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.045, green: 0.061, blue: 0.105, alpha: 1)
        configureView()
        updatePrivacyState(isHidden: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cardGradient.frame = walletCard.bounds
        cardGlow.frame = CGRect(x: walletCard.bounds.width * 0.34, y: -90,
                                width: walletCard.bounds.width * 0.86, height: 340)
    }

    private func configureView() {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -35),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        let topRow = UIStackView()
        topRow.axis = .horizontal
        topRow.alignment = .center
        let titles = UIStackView()
        titles.axis = .vertical
        titles.spacing = 4
        let title = makeLabel("Мой кошелёк", size: 29, weight: .bold, color: .white)
        let subtitle = makeLabel("iOS · Particle Privacy Demo", size: 13, weight: .regular,
                                 color: UIColor(white: 0.63, alpha: 1))
        titles.addArrangedSubview(title)
        titles.addArrangedSubview(subtitle)
        topRow.addArrangedSubview(titles)
        topRow.addArrangedSubview(UIView())
        let demoBadge = makeLabel("DEMO", size: 11, weight: .heavy,
                                  color: UIColor(red: 0.60, green: 0.82, blue: 1, alpha: 1))
        demoBadge.textAlignment = .center
        demoBadge.backgroundColor = UIColor(red: 0.14, green: 0.22, blue: 0.34, alpha: 1)
        demoBadge.layer.cornerRadius = 10
        demoBadge.clipsToBounds = true
        demoBadge.widthAnchor.constraint(equalToConstant: 66).isActive = true
        demoBadge.heightAnchor.constraint(equalToConstant: 29).isActive = true
        topRow.addArrangedSubview(demoBadge)
        content.addArrangedSubview(topRow)
        addGap(30, to: content)

        walletCard.layer.cornerRadius = 26
        walletCard.layer.cornerCurve = .continuous
        walletCard.clipsToBounds = true
        walletCard.translatesAutoresizingMaskIntoConstraints = false
        walletCard.heightAnchor.constraint(equalToConstant: 285).isActive = true
        cardGradient.colors = [
            UIColor(red: 0.26, green: 0.31, blue: 0.73, alpha: 1).cgColor,
            UIColor(red: 0.15, green: 0.20, blue: 0.47, alpha: 1).cgColor,
            UIColor(red: 0.08, green: 0.12, blue: 0.28, alpha: 1).cgColor
        ]
        cardGradient.locations = [0, 0.45, 1]
        cardGradient.startPoint = CGPoint(x: 0, y: 0)
        cardGradient.endPoint = CGPoint(x: 1, y: 1)
        walletCard.layer.addSublayer(cardGradient)
        cardGlow.type = .radial
        cardGlow.colors = [UIColor(red: 0.44, green: 0.59, blue: 1, alpha: 0.33).cgColor,
                           UIColor(red: 0.44, green: 0.59, blue: 1, alpha: 0).cgColor]
        cardGlow.startPoint = CGPoint(x: 0.5, y: 0.4)
        cardGlow.endPoint = CGPoint(x: 1, y: 1)
        walletCard.layer.addSublayer(cardGlow)
        content.addArrangedSubview(walletCard)

        let cardTop = UIStackView()
        cardTop.axis = .horizontal
        cardTop.alignment = .center
        cardTop.translatesAutoresizingMaskIntoConstraints = false
        walletCard.addSubview(cardTop)
        let coinIcon = makeCircleSymbol("diamond.fill", bg: UIColor.white.withAlphaComponent(0.16))
        coinIcon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        coinIcon.heightAnchor.constraint(equalToConstant: 40).isActive = true
        cardTop.addArrangedSubview(coinIcon)
        cardTop.setCustomSpacing(10, after: coinIcon)
        cardTop.addArrangedSubview(makeLabel("Main Wallet", size: 17, weight: .semibold, color: .white))
        cardTop.addArrangedSubview(UIView())
        let dots = UIImageView(image: UIImage(systemName: "ellipsis"))
        dots.tintColor = .white.withAlphaComponent(0.75)
        dots.contentMode = .scaleAspectFit
        dots.widthAnchor.constraint(equalToConstant: 24).isActive = true
        cardTop.addArrangedSubview(dots)

        let caption = makeLabel("ОБЩИЙ БАЛАНС", size: 11, weight: .bold,
                                color: UIColor.white.withAlphaComponent(0.67))
        caption.textAlignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false
        walletCard.addSubview(caption)

        balanceView.translatesAutoresizingMaskIntoConstraints = false
        walletCard.addSubview(balanceView)
        balanceView.onStateChanged = { [weak self] isHidden in
            self?.updatePrivacyState(isHidden: isHidden)
        }

        privacyButton.setTitleColor(.white, for: .normal)
        privacyButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        privacyButton.tintColor = .white
        privacyButton.translatesAutoresizingMaskIntoConstraints = false
        privacyButton.addTarget(self, action: #selector(togglePrivacy), for: .touchUpInside)
        walletCard.addSubview(privacyButton)

        NSLayoutConstraint.activate([
            cardTop.leadingAnchor.constraint(equalTo: walletCard.leadingAnchor, constant: 24),
            cardTop.trailingAnchor.constraint(equalTo: walletCard.trailingAnchor, constant: -24),
            cardTop.topAnchor.constraint(equalTo: walletCard.topAnchor, constant: 24),
            caption.centerXAnchor.constraint(equalTo: walletCard.centerXAnchor),
            caption.topAnchor.constraint(equalTo: cardTop.bottomAnchor, constant: 23),
            balanceView.leadingAnchor.constraint(equalTo: walletCard.leadingAnchor, constant: 14),
            balanceView.trailingAnchor.constraint(equalTo: walletCard.trailingAnchor, constant: -14),
            balanceView.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 2),
            balanceView.heightAnchor.constraint(equalToConstant: 104),
            privacyButton.centerXAnchor.constraint(equalTo: walletCard.centerXAnchor),
            privacyButton.bottomAnchor.constraint(equalTo: walletCard.bottomAnchor, constant: -9),
            privacyButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        addGap(12, to: content)
        stateLabel.textAlignment = .center
        stateLabel.numberOfLines = 0
        stateLabel.font = UIFont.systemFont(ofSize: 13)
        stateLabel.textColor = UIColor(white: 0.59, alpha: 1)
        content.addArrangedSubview(stateLabel)
        addGap(30, to: content)

        let actionsRow = UIStackView()
        actionsRow.axis = .horizontal
        actionsRow.distribution = .fillEqually
        actionsRow.spacing = 12
        for (icon, title) in [("arrow.up.right", "Отправить"), ("arrow.down.left", "Получить"), ("arrow.left.arrow.right", "Обмен") ] {
            let holder = UIStackView()
            holder.axis = .vertical
            holder.spacing = 10
            holder.alignment = .center
            let circle = makeCircleSymbol(icon, bg: UIColor(red: 0.12, green: 0.16, blue: 0.26, alpha: 1))
            circle.widthAnchor.constraint(equalToConstant: 60).isActive = true
            circle.heightAnchor.constraint(equalToConstant: 60).isActive = true
            circle.layer.cornerRadius = 21
            holder.addArrangedSubview(circle)
            holder.addArrangedSubview(makeLabel(title, size: 12, weight: .medium, color: UIColor(white: 0.78, alpha: 1)))
            actionsRow.addArrangedSubview(holder)
        }
        content.addArrangedSubview(actionsRow)
        addGap(39, to: content)

        content.addArrangedSubview(makeLabel("Активы", size: 21, weight: .bold, color: .white))
        addGap(13, to: content)
        content.addArrangedSubview(assetRow(symbol: "diamond.fill", name: "Toncoin", ticker: "TON · 15.42", balance: "$93.88", color: .systemCyan))
        addGap(1, to: content)
        content.addArrangedSubview(assetRow(symbol: "dollarsign", name: "Tether", ticker: "USD₮ · 12,389.43", balance: "$12,389.43", color: UIColor(red: 0.25, green: 0.72, blue: 0.60, alpha: 1)))
        addGap(30, to: content)

        let note = makeLabel("Независимое демо эффекта. Баланс и токены вымышленные.\nНикаких сетевых запросов, ключей или операций с кошельком.", size: 12, weight: .regular, color: UIColor(white: 0.47, alpha: 1))
        note.numberOfLines = 0
        note.textAlignment = .center
        content.addArrangedSubview(note)
    }

    private func assetRow(symbol: String, name: String, ticker: String, balance: String, color: UIColor) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        let icon = makeCircleSymbol(symbol, bg: color)
        icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 44).isActive = true
        row.addArrangedSubview(icon)
        let left = UIStackView()
        left.axis = .vertical
        left.spacing = 4
        left.addArrangedSubview(makeLabel(name, size: 15, weight: .semibold, color: .white))
        left.addArrangedSubview(makeLabel(ticker, size: 12, weight: .regular, color: UIColor(white: 0.55, alpha: 1)))
        row.addArrangedSubview(left)
        row.addArrangedSubview(UIView())
        let amount = makeLabel(balance, size: 15, weight: .semibold, color: .white)
        assetAmounts.append((amount, balance))
        row.addArrangedSubview(amount)
        let container = UIView()
        container.backgroundColor = UIColor(red: 0.085, green: 0.108, blue: 0.18, alpha: 1)
        container.layer.cornerRadius = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -15),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 76)
        ])
        return container
    }

    private func makeCircleSymbol(_ name: String, bg: UIColor) -> UIView {
        let outer = UIView()
        outer.backgroundColor = bg
        outer.layer.cornerRadius = 20
        let symbol = UIImageView(image: UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)))
        symbol.tintColor = .white
        symbol.translatesAutoresizingMaskIntoConstraints = false
        outer.addSubview(symbol)
        NSLayoutConstraint.activate([symbol.centerXAnchor.constraint(equalTo: outer.centerXAnchor), symbol.centerYAnchor.constraint(equalTo: outer.centerYAnchor)])
        return outer
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.text = text
        return label
    }

    private func addGap(_ amount: CGFloat, to stack: UIStackView) {
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: amount).isActive = true
        stack.addArrangedSubview(spacer)
    }

    private func updatePrivacyState(isHidden: Bool) {
        let text = isHidden ? "Показать баланс" : "Скрыть баланс"
        privacyButton.setTitle("\(isHidden ? "◉" : "◌")  \(text)", for: .normal)
        for item in assetAmounts { item.label.text = isHidden ? "••••••" : item.original }
        stateLabel.text = isHidden
            ? "Проведи пальцем по частицам или нажми, чтобы раскрыть"
            : "Нажми на сумму — цифры рассыплются на частицы"
    }

    @objc private func togglePrivacy() { balanceView.toggle() }
}
