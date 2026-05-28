document.getElementById("formCurriculo").addEventListener("submit", function(e) {
  e.preventDefault();

  const nome = document.getElementById("nome").value;
  const email = document.getElementById("email").value;
  const telefone = document.getElementById("telefone").value;
  const objetivo = document.getElementById("objetivo").value;
  const experiencia = document.getElementById("experiencia").value;
  const habilidades = document.getElementById("habilidades").value;

  document.getElementById("resultado").innerHTML = `
    <h2>${nome}</h2>
    <p>📧 ${email}</p>
    <p>📱 ${telefone}</p>

    <h3>🎯 Objetivo</h3>
    <p>${objetivo || "Não informado"}</p>

    <h3>💼 Experiência</h3>
    <p>${experiencia || "Não informado"}</p>

    <h3>⚡ Habilidades</h3>
    <p>${habilidades || "Não informado"}</p>
  `;
});