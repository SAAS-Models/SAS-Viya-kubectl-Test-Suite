from setuptools import setup, find_packages

with open("README.md", "r") as fh:
    long_description = fh.read()

with open("requirements.txt", "r") as fh:
    requirements = fh.read().splitlines()

setup(
    name="sas-viya-kubectl-tests",
    version="1.0.0",
    author="Your Organization",
    author_email="your-email@example.com",
    description="kubectl-based testing framework for SAS Viya 4 on Kubernetes",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/sas-viya-kubectl-tests",
    packages=find_packages(where="lib/python"),
    package_dir={"": "lib/python"},
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    entry_points={
        "console_scripts": [
            "sas-viya-test=lib.python.cli:main",
        ],
    },
)
