document.getElementById("applyBtn").addEventListener("click", function () {
  const msg = document.getElementById("msg");

  msg.textContent = "✔ Candidatura enviada com sucesso!";
  msg.style.color = "green";

  this.disabled = true;
  this.textContent = "Candidatado";
});