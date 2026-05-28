const search = document.getElementById("search");
const cards = document.querySelectorAll(".card");

search.addEventListener("input", function () {
  const value = this.value.toLowerCase();

  cards.forEach(card => {
    const nome = card.querySelector(".nome").textContent.toLowerCase();
    const area = card.querySelector(".area").textContent.toLowerCase();

    if (nome.includes(value) || area.includes(value)) {
      card.style.display = "block";
    } else {
      card.style.display = "none";
    }
  });
});

// botão conectar
document.querySelectorAll(".connect").forEach(btn => {
  btn.addEventListener("click", function () {
    if (this.textContent === "Conectar") {
      this.textContent = "Conectado";
      this.style.background = "green";
    } else {
      this.textContent = "Conectar";
      this.style.background = "#4f46e5";
    }
  });
});