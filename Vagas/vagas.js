const search = document.getElementById("search");
const cards = document.querySelectorAll(".card");

search.addEventListener("input", function () {
  const valor = this.value.toLowerCase();

  cards.forEach(card => {
    const titulo = card.querySelector(".titulo").textContent.toLowerCase();
    const empresa = card.querySelector(".empresa").textContent.toLowerCase();

    if (titulo.includes(valor) || empresa.includes(valor)) {
      card.style.display = "block";
    } else {
      card.style.display = "none";
    }
  });
});